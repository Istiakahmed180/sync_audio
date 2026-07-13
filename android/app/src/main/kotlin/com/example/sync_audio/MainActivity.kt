package com.example.sync_audio

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import java.security.KeyStore

class MainActivity : FlutterActivity() {
    private val playbackChannelName = "sync_audio/audio_track"
    private val systemAudioChannelName = "sync_audio/system_audio_capture"
    private val systemAudioStreamChannelName = "sync_audio/system_audio_stream"
    private val calibrationChannelName = "sync_audio/calibration"
    private val pairingChannelName = "sync_audio/pairing"
    private val projectionRequestCode = 7002
    private val microphonePermissionRequestCode = 7003
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val audioLock = Any()
    private var audioTrack: AudioTrack? = null
    private var pendingSystemAudioStartResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        try {
                            initializeAudioTrack()
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("AUDIO_INIT_FAILED", "Unable to initialize AudioTrack", null)
                        }
                    }
                    "writePcm" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data == null) {
                            result.error("INVALID_PCM", "PCM data is missing", null)
                            return@setMethodCallHandler
                        }
                        audioExecutor.execute {
                            val written = synchronized(audioLock) {
                                audioTrack?.write(data, 0, data.size, AudioTrack.WRITE_BLOCKING) ?: -1
                            }
                            runOnUiThread { result.success(written) }
                        }
                    }
                    "stop" -> {
                        stopAudioTrack()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, systemAudioStreamChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SystemAudioPcmBus.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    SystemAudioPcmBus.sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemAudioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> requestSystemAudioCapture(result)
                    "stop" -> {
                        stopService(Intent(this, SystemAudioCaptureService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, calibrationChannelName)
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences("sync_audio", MODE_PRIVATE)
                when (call.method) {
                    "read" -> {
                        val receiverId = call.arguments as? String
                        if (receiverId == null) {
                            result.error("INVALID_RECEIVER", "Receiver ID is missing", null)
                        } else {
                            val value = preferences.getLong("calibration_$receiverId", 0L)
                            result.success(value.toInt())
                        }
                    }
                    "write" -> {
                        val receiverId = call.argument<String>("receiverId")
                        val calibration = call.argument<Number>("calibrationMicros")
                        if (receiverId == null || calibration == null) {
                            result.error("INVALID_CALIBRATION", "Calibration data is missing", null)
                        } else {
                            preferences.edit()
                                .putLong("calibration_$receiverId", calibration.toLong())
                                .apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pairingChannelName)
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences("sync_audio", MODE_PRIVATE)
                when (call.method) {
                    "read" -> result.success(readEncryptedPairingToken(preferences))
                    "write" -> {
                        val token = call.arguments as? String
                        if (token == null || token.length < 6) {
                            result.error("INVALID_PAIRING_TOKEN", "Pairing token is invalid", null)
                        } else {
                            writeEncryptedPairingToken(preferences, token)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pairingKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(PAIRING_KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                PAIRING_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun writeEncryptedPairingToken(
        preferences: android.content.SharedPreferences,
        token: String,
    ) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, pairingKey())
        val nonce = cipher.iv
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        val value = "${Base64.encodeToString(nonce, Base64.NO_WRAP)}:${Base64.encodeToString(encrypted, Base64.NO_WRAP)}"
        preferences.edit().putString(PAIRING_VALUE_KEY, value).remove("pairing_token").apply()
    }

    private fun readEncryptedPairingToken(
        preferences: android.content.SharedPreferences,
    ): String? {
        val stored = preferences.getString(PAIRING_VALUE_KEY, null) ?: run {
            // Legacy plaintext values are intentionally not migrated in place.
            preferences.edit().remove("pairing_token").apply()
            return null
        }
        return try {
            val parts = stored.split(':', limit = 2)
            if (parts.size != 2) return null
            val nonce = Base64.decode(parts[0], Base64.NO_WRAP)
            val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, pairingKey(), javax.crypto.spec.GCMParameterSpec(128, nonce))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun requestSystemAudioCapture(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("SYSTEM_AUDIO_UNSUPPORTED", "System audio capture requires Android 10 or newer", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingSystemAudioStartResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphonePermissionRequestCode)
            return
        }
        launchProjectionConsent(result)
    }

    private fun launchProjectionConsent(result: MethodChannel.Result) {
        pendingSystemAudioStartResult = result
        val manager = getSystemService(MediaProjectionManager::class.java)
        startActivityForResult(manager.createScreenCaptureIntent(), projectionRequestCode)
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != projectionRequestCode) return
        val result = pendingSystemAudioStartResult
        pendingSystemAudioStartResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.error("MEDIA_PROJECTION_DENIED", "System audio capture permission was denied", null)
            return
        }
        try {
            val serviceIntent = Intent(this, SystemAudioCaptureService::class.java)
                .putExtra(SystemAudioCaptureService.EXTRA_RESULT_CODE, resultCode)
                .putExtra(SystemAudioCaptureService.EXTRA_PROJECTION_DATA, data)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            result.success(null)
        } catch (_: Exception) {
            result.error("SYSTEM_AUDIO_START_FAILED", "Unable to start system audio capture", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != microphonePermissionRequestCode) return
        val result = pendingSystemAudioStartResult
        pendingSystemAudioStartResult = null
        if (result == null) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            launchProjectionConsent(result)
        } else {
            result.error("MICROPHONE_PERMISSION_DENIED", "Audio capture permission was denied", null)
        }
    }

    private fun initializeAudioTrack() {
        synchronized(audioLock) {
            if (audioTrack != null) return
            val sampleRate = 48000
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes((minBufferSize.coerceAtLeast(4096)) * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            audioTrack?.play()
        }
    }

    private fun stopAudioTrack() {
        synchronized(audioLock) {
            audioTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop()
                track.flush()
                track.release()
            }
            audioTrack = null
        }
    }

    override fun onDestroy() {
        stopAudioTrack()
        audioExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val PAIRING_KEY_ALIAS = "sync_audio_pairing_key"
        private const val PAIRING_VALUE_KEY = "pairing_token_v2"
    }
}
