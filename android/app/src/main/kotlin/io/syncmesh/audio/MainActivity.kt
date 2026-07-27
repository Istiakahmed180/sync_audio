package io.syncmesh.audio

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.provider.Settings
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
import java.net.InetAddress

class MainActivity : FlutterActivity() {
    private val playbackChannelName = "sync_audio/audio_track"
    private val systemAudioChannelName = "sync_audio/system_audio_capture"
    private val systemAudioStreamChannelName = "sync_audio/system_audio_stream"
    private val calibrationChannelName = "sync_audio/calibration"
    private val pairingChannelName = "sync_audio/pairing"
    private val nativeAudioChannelName = "sync_audio/native_audio"
    private val audioOutputChannelName = "sync_audio/audio_output"
    private val projectionRequestCode = 7002
    private val microphonePermissionRequestCode = 7003
    private val notificationPermissionRequestCode = 7004
    private val bluetoothPermissionRequestCode = 7005
    private val notificationChannelId = "sync_audio_status"
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val audioLock = Any()
    private var audioTrack: AudioTrack? = null
    private var pendingSystemAudioStartResult: MethodChannel.Result? = null
    private var projectionRequestInFlight = false
    private var pendingNativeSender: NativeUdpAudioSender? = null
    private var nativeSender: NativeUdpAudioSender? = null
    private var nativeReceiver: NativeUdpAudioReceiver? = null
    private var pendingNotification: Triple<Int, String, String>? = null
    private var pendingMediaNotification: MediaNotificationArgs? = null
    private var preferredOutputDeviceId: Int? = null
    private var preferredOutputName: String? = null
    private var preferredOutputType: Int? = null
    private var restoringOutputRoute = false
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            restoreOutputAfterDeviceChange(addedDevices.toList())
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            restoreOutputAfterDeviceChange(removedDevices.toList())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getSystemService(AudioManager::class.java).registerAudioDeviceCallback(
                audioDeviceCallback,
                Handler(Looper.getMainLooper()),
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioOutputChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openOutputSettings" -> {
                        startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
                        result.success(null)
                    }

                    "listOutputs" -> try {
                        val outputs = listAudioOutputs()
                        Log.i("SyncAudioOutput", "Found ${outputs.size} audio outputs")
                        result.success(outputs)
                    } catch (error: Exception) {
                        Log.e("SyncAudioOutput", "Could not list audio outputs", error)
                        result.error("OUTPUT_LIST_FAILED", error.message, null)
                    }

                    "selectOutput" -> {
                        val id = (call.arguments as? String)?.toIntOrNull()
                        if (id == null) {
                            result.error("INVALID_OUTPUT", "Audio output ID is invalid", null)
                        } else {
                            preferredOutputDeviceId = id
                            val device = getSystemService(AudioManager::class.java)
                                .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                                .firstOrNull { it.id == id }
                            device?.let {
                                preferredOutputName = it.productName?.toString()?.trim()
                                preferredOutputType = it.type
                            }
                            val selected = synchronized(audioLock) {
                                val flutterSelected = if (device == null) {
                                    false
                                } else {
                                    // setPreferredDevice is ignored by some
                                    // Android builds while AudioTrack is
                                    // already playing. Recreate the track so
                                    // Bluetooth <-> system changes use the
                                    // correct route and buffer profile.
                                    if (audioTrack != null) {
                                        stopAudioTrack()
                                        initializeAudioTrack()
                                    } else {
                                        // The preferred ID is retained and
                                        // applied when playback is started.
                                        true
                                    }
                                }
                                val nativeSelected = if (device == null) {
                                    false
                                } else {
                                    nativeReceiver?.setPreferredOutputDevice(device) ?: true
                                }
                                flutterSelected && nativeSelected
                            }
                            if (selected == false) {
                                result.error(
                                    "OUTPUT_SELECT_FAILED",
                                    "Could not select audio output",
                                    null
                                )
                            } else {
                                result.success(null)
                            }
                        }
                    }

                    "reapplyOutput" -> {
                        try {
                            synchronized(audioLock) {
                                if (audioTrack != null) {
                                    stopAudioTrack()
                                    if (!initializeAudioTrack()) {
                                        error("Could not reapply the selected output")
                                    }
                                }
                                nativeReceiver?.let { receiver ->
                                    findPreferredOutput()?.let(receiver::setPreferredOutputDevice)
                                }
                            }
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "OUTPUT_RESTORE_FAILED",
                                error.message,
                                null,
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_audio/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val title = call.argument<String>("title") ?: "SyncMesh Audio"
                        val message = call.argument<String>("message")
                        val id = call.argument<Int>("id") ?: 1001
                        if (message == null) {
                            result.error(
                                "INVALID_NOTIFICATION",
                                "Notification message is missing",
                                null
                            )
                        } else {
                            showStatusNotification(id, title, message)
                            result.success(null)
                        }
                    }

                    "showMedia" -> {
                        showMediaNotification(
                            id = call.argument<Int>("id") ?: 1001,
                            title = call.argument<String>("title") ?: "SyncMesh Audio",
                            message = call.argument<String>("message") ?: "SyncMesh Audio",
                            isPlaying = call.argument<Boolean>("isPlaying") ?: false,
                            isMuted = call.argument<Boolean>("isMuted") ?: false,
                        )
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_audio/battery_optimization")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val powerManager = getSystemService(android.os.PowerManager::class.java)
                        result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_audio/notification_actions")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationActionSink = events
                    pendingNotificationAction?.let {
                        events?.success(it)
                        pendingNotificationAction = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    notificationActionSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_audio/background_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, NetworkKeepAliveService::class.java)
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(null)
                        } catch (error: RuntimeException) {
                            // Android may reject a dataSync foreground service
                            // after its rolling time budget is exhausted.
                            Log.w("MainActivity", "Unable to start network keep-alive service", error)
                            result.error(
                                "BACKGROUND_SERVICE_UNAVAILABLE",
                                "Android temporarily rejected background connection keep-alive",
                                null,
                            )
                        }
                    }

                    "stop" -> {
                        stopService(Intent(this, NetworkKeepAliveService::class.java))
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_audio/device_info")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceName" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                    "getDeviceInfo" -> result.success(
                        mapOf(
                            "platform" to "Android",
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "deviceName" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                            "osVersion" to Build.VERSION.RELEASE,
                            "androidVersion" to Build.VERSION.RELEASE,
                            "sdk" to Build.VERSION.SDK_INT,
                        ),
                    )

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeAudioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startNativeHostStream" -> {
                        if (isEmulator()) {
                            result.error(
                                "EMULATOR_UNSUPPORTED",
                                "System audio capture is not available on emulators",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        val codec = call.argument<String>("codec") ?: "pcm16"
                        val encrypted = call.argument<Boolean>("encrypted") ?: false
                        val destinations = call.argument<List<String>>("destinations")
                        val port = call.argument<Int>("port")
                        val mode = call.argument<String>("latencyMode") ?: "balanced"
                        val sessionId = call.argument<String>("sessionId")
                        val pairingToken = call.argument<String>("pairingToken")
                        if (codec !in listOf("pcm16", "opus") || destinations.isNullOrEmpty() || port == null || sessionId == null ||
                            (encrypted && pairingToken.isNullOrEmpty())
                        ) {
                            result.error(
                                "NATIVE_PATH_UNAVAILABLE",
                                "Native path requires PCM16 or Opus and valid stream security settings",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val nativeCodec = if (codec == "opus") NativeAudioPacket.CODEC_OPUS else NativeAudioPacket.CODEC_PCM16
                            if (nativeCodec == NativeAudioPacket.CODEC_OPUS && !OpusCodecNative.isAvailable()) {
                                result.error("NATIVE_OPUS_UNAVAILABLE", "Native Opus is unavailable", null)
                                return@setMethodCallHandler
                            }
                            pendingNativeSender?.stop()
                            pendingNativeSender = NativeUdpAudioSender(
                                destinations = destinations.map(InetAddress::getByName),
                                port = port,
                                targetDelayMicros = latencyDelayMicros(mode),
                                sessionId = sessionId,
                                pairingToken = if (encrypted) pairingToken else null,
                                codec = nativeCodec,
                            )
                            requestSystemAudioCapture(result, pendingNativeSender)
                        } catch (error: Exception) {
                            pendingNativeSender = null
                            result.error("NATIVE_HOST_INIT_FAILED", error.message, null)
                        }
                    }

                    "stopNativeHostStream" -> {
                        stopService(Intent(this, SystemAudioCaptureService::class.java))
                        nativeSender?.stop()
                        pendingNativeSender?.stop()
                        nativeSender = null
                        pendingNativeSender = null
                        result.success(null)
                    }

                    "addNativeHostReceivers" -> {
                        val destinations = call.argument<List<String>>("destinations")
                        if (destinations.isNullOrEmpty()) {
                            result.error("INVALID_DESTINATIONS", "No receivers supplied", null)
                        } else if (nativeSender == null) {
                            result.error("NATIVE_HOST_NOT_RUNNING", "Native host is not running", null)
                        } else {
                            nativeSender?.addDestinations(destinations.map(InetAddress::getByName))
                            result.success(null)
                        }
                    }

                    "startNativeReceiver" -> {
                        val port = call.argument<Int>("port")
                        val mode = call.argument<String>("latencyMode") ?: "balanced"
                        val codec = call.argument<String>("codec") ?: "pcm16"
                        val sessionId = call.argument<String>("sessionId")
                        val pairingToken = call.argument<String>("pairingToken")
                        if (port == null || codec !in listOf("pcm16", "opus")) {
                            result.error("INVALID_NATIVE_CODEC", "Native receiver port or codec is invalid", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val nativeCodec = if (codec == "opus") NativeAudioPacket.CODEC_OPUS else NativeAudioPacket.CODEC_PCM16
                            if (nativeCodec == NativeAudioPacket.CODEC_OPUS && !OpusCodecNative.isAvailable()) {
                                result.error("NATIVE_OPUS_UNAVAILABLE", "Native Opus is unavailable", null)
                                return@setMethodCallHandler
                            }
                            nativeReceiver?.stop()
                            val candidate = NativeUdpAudioReceiver(
                                port = port,
                                latencyMode = mode,
                                sessionId = sessionId,
                                pairingToken = pairingToken,
                                codec = nativeCodec,
                                audioManager = getSystemService(AudioManager::class.java),
                            )
                            try {
                                candidate.start()
                                nativeReceiver = candidate
                            } catch (error: Exception) {
                                candidate.stop()
                                throw error
                            }
                            result.success(null)
                        } catch (error: Exception) {
                            nativeReceiver = null
                            result.error("NATIVE_RECEIVER_INIT_FAILED", error.message, null)
                        }
                    }

                    "stopNativeReceiver" -> {
                        nativeReceiver?.stop()
                        nativeReceiver = null
                        result.success(null)
                    }

                    "getNativeDiagnostics" -> result.success(
                        when {
                            nativeSender != null -> nativeSender?.diagnostics() ?: mapOf("path" to "native_sender_null")
                            nativeReceiver != null -> nativeReceiver?.diagnostics() ?: mapOf("path" to "native_receiver_null")
                            else -> mapOf("path" to "dart_fallback")
                        },
                    )

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        try {
                            initializeAudioTrack()
                            result.success(null)
                        } catch (_: Exception) {
                            result.error(
                                "AUDIO_INIT_FAILED",
                                "Unable to initialize AudioTrack",
                                null
                            )
                        }
                    }

                    "writePcm" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data == null) {
                            result.error("INVALID_PCM", "PCM data is missing", null)
                            return@setMethodCallHandler
                        }
                        audioExecutor.execute {
                            // Do not hold audioLock during a potentially
                            // blocking AudioTrack call. A route change can
                            // release/recreate the track on the main thread;
                            // holding the lock here can otherwise deadlock the
                            // UI and trigger an ANR when AudioFlinger is down.
                            val track = synchronized(audioLock) { audioTrack }
                            val written = try {
                                track?.write(data, 0, data.size, AudioTrack.WRITE_NON_BLOCKING)
                                    ?: -1
                            } catch (_: IllegalStateException) {
                                // stop() may race with a queued PCM write. The
                                // receiver will restart the track on demand.
                                -1
                            } catch (_: IllegalArgumentException) {
                                -1
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
                    "start" -> {
                        if (isEmulator()) {
                            result.error(
                                "EMULATOR_UNSUPPORTED",
                                "System audio capture is not available on emulators",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        requestSystemAudioCapture(result)
                    }
                    "stop" -> {
                        stopService(Intent(this, SystemAudioCaptureService::class.java))
                        nativeSender?.stop()
                        nativeSender = null
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
        val value = "${Base64.encodeToString(nonce, Base64.NO_WRAP)}:${
            Base64.encodeToString(
                encrypted,
                Base64.NO_WRAP
            )
        }"
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
            cipher.init(
                Cipher.DECRYPT_MODE,
                pairingKey(),
                javax.crypto.spec.GCMParameterSpec(128, nonce)
            )
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun requestSystemAudioCapture(
        result: MethodChannel.Result,
        nativeSender: NativeUdpAudioSender? = null,
    ) {
        Log.i(
            "SyncAudioCapture",
            "requestSystemAudioCapture inFlight=$projectionRequestInFlight pending=${pendingSystemAudioStartResult != null}"
        )
        if (projectionRequestInFlight || pendingSystemAudioStartResult != null) {
            result.error(
                "SYSTEM_AUDIO_START_IN_PROGRESS",
                "System audio capture is already starting",
                null
            )
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "SYSTEM_AUDIO_UNSUPPORTED",
                "System audio capture requires Android 10 or newer",
                null
            )
            return
        }
        pendingNativeSender = nativeSender
        pendingSystemAudioStartResult = result
        startProjectionFlow()
    }

    private fun startProjectionFlow() {
        val result = pendingSystemAudioStartResult ?: return
        projectionRequestInFlight = true
        try {
            // Do not start the mediaProjection foreground service before the
            // user grants screen-capture consent. Android 14+ rejects that
            // pre-consent promotion with a SecurityException. The service is
            // started from onActivityResult after projection data is available.
            val manager = getSystemService(MediaProjectionManager::class.java)
            val captureIntent = if (Build.VERSION.SDK_INT >= 34) {
                manager.createScreenCaptureIntent(
                    MediaProjectionConfig.createConfigForDefaultDisplay(),
                )
            } else {
                manager.createScreenCaptureIntent()
            }
            startActivityForResult(captureIntent, projectionRequestCode)
        } catch (error: Exception) {
            pendingSystemAudioStartResult = null
            projectionRequestInFlight = false
            pendingNativeSender?.stop()
            pendingNativeSender = null
            result.error(
                "SYSTEM_AUDIO_START_FAILED",
                "Unable to start system audio capture: ${error.message}",
                null,
            )
        }
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != projectionRequestCode) return
        Log.i("SyncAudioCapture", "projection result resultCode=$resultCode data=${data != null}")
        val result = pendingSystemAudioStartResult
        pendingSystemAudioStartResult = null
        projectionRequestInFlight = false
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            stopService(Intent(this, SystemAudioCaptureService::class.java))
            pendingNativeSender?.stop()
            pendingNativeSender = null
            result.error(
                "MEDIA_PROJECTION_DENIED",
                "System audio capture permission was denied",
                null,
            )
            return
        }
        try {
            pendingNativeSender?.start()
            nativeSender = pendingNativeSender
            pendingNativeSender = null
            // Keep a static copy of the consent result as a fallback; some
            // Android 13+ builds drop the parcelable extra when the Intent is
            // forwarded into the foreground service.
            SystemAudioCaptureService.pendingResultCode = resultCode
            SystemAudioCaptureService.pendingProjectionData = data
            val serviceIntent = Intent(this, SystemAudioCaptureService::class.java)
                .setAction(SystemAudioCaptureService.ACTION_START)
                .putExtra(SystemAudioCaptureService.EXTRA_RESULT_CODE, resultCode)
                .putExtra(SystemAudioCaptureService.EXTRA_PROJECTION_DATA, data)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            result.success(null)
        } catch (error: Exception) {
            stopService(Intent(this, SystemAudioCaptureService::class.java))
            nativeSender?.stop()
            nativeSender = null
            pendingNativeSender?.stop()
            pendingNativeSender = null
            result.error(
                "SYSTEM_AUDIO_START_FAILED",
                "Unable to start system audio capture: ${error.message}",
                null,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                pendingMediaNotification?.let { media ->
                    pendingMediaNotification = null
                    showMediaNotification(
                        media.id,
                        media.title,
                        media.message,
                        media.isPlaying,
                        media.isMuted,
                    )
                }
                pendingNotification?.let { (id, title, message) ->
                    pendingNotification = null
                    showStatusNotification(id, title, message)
                }
            } else {
                pendingNotification = null
            }
            return
        }
        if (requestCode != microphonePermissionRequestCode) return
        val result = pendingSystemAudioStartResult
        if (result == null) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startProjectionFlow()
        } else {
            pendingSystemAudioStartResult = null
            pendingNativeSender?.stop()
            pendingNativeSender = null
            result.error(
                "MICROPHONE_PERMISSION_DENIED",
                "Audio capture permission was denied",
                null,
            )
        }
    }

    private fun showStatusNotification(id: Int, title: String, message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                notificationChannelId,
                "SyncMesh Audio status",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Connection and audio status updates"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotification = Triple(id, title, message)
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
            return
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_sync_audio)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .build()
        getSystemService(NotificationManager::class.java).notify(
            id,
            notification,
        )
    }

    private fun showMediaNotification(
        id: Int,
        title: String,
        message: String,
        isPlaying: Boolean,
        isMuted: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    notificationChannelId,
                    "SyncMesh Audio controls",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Start, stop, mute and volume controls for SyncMesh Audio"
                },
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingMediaNotification = MediaNotificationArgs(id, title, message, isPlaying, isMuted)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequestCode)
            return
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_sync_audio)
            .setContentTitle(title)
            .setContentText(message)
            .setOngoing(isPlaying)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .addAction(notificationAction("volume_down", "Volume −"))
            .addAction(notificationAction("mute", if (isMuted) "Unmute" else "Mute"))
            .addAction(notificationAction(if (isPlaying) "stop" else "start", if (isPlaying) "Stop" else "Start"))
            .addAction(notificationAction("volume_up", "Volume +"))
            .build()
        getSystemService(NotificationManager::class.java).notify(id, notification)
    }

    private fun notificationAction(action: String, label: String): Notification.Action {
        val intent = Intent(this, NotificationActionReceiver::class.java)
                .setAction("io.syncmesh.audio.NOTIFICATION_$action")
        val pending = PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, label, pending).build()
    }

    private fun initializeAudioTrack(): Boolean {
    synchronized(audioLock) {
            if (audioTrack != null) return true
            val sampleRate = 48000
            val audioManager = getSystemService(AudioManager::class.java)
            val bluetoothRoute = currentBluetoothOutput(audioManager) != null
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            if (!bluetoothRoute) attributes.setFlags(AudioAttributes.FLAG_LOW_LATENCY)
            val bufferDurationMs = if (bluetoothRoute) 120 else 20
            val bufferBytes = (sampleRate / 1000 * bufferDurationMs * 2)
            val builder = AudioTrack.Builder()
                .setAudioAttributes(attributes.build())
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(minBufferSize.coerceAtLeast(bufferBytes))
                .setTransferMode(AudioTrack.MODE_STREAM)
            if (!bluetoothRoute) {
                builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            }
            audioTrack = builder.build()
            check(audioTrack?.state == AudioTrack.STATE_INITIALIZED) {
                "AudioTrack failed to initialize"
            }
            var preferredApplied = true
            if (preferredOutputDeviceId != null || preferredOutputName != null) {
                findPreferredOutput()?.let {
                    // Android's built-in speaker/earpiece is already the
                    // system default route. Forcing it through
                    // setPreferredDevice can make some OEM AudioFlinger
                    // implementations repeatedly recreate a dead track.
                    preferredApplied = !isBluetoothOutput(it) ||
                            audioTrack?.setPreferredDevice(it) == true
                }
            }
            audioTrack?.play()
            findPreferredOutput()?.let { device ->
                val applied = if (isBluetoothOutput(device)) {
                    audioTrack?.setPreferredDevice(device)
                } else {
                    true
                }
                Log.i(
                    "SyncAudioOutput",
                    "Preferred output ${device.productName} (${device.id}) applied=$applied"
                )
            }
            return preferredApplied
        }
    }

    private fun currentBluetoothOutput(audioManager: AudioManager): AudioDeviceInfo? {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        if (preferredOutputDeviceId != null || preferredOutputName != null) {
            return findPreferredOutput(outputs)?.takeIf(::isBluetoothOutput)
        }
        return outputs.firstOrNull(::isBluetoothOutput)
    }

    private fun findPreferredOutput(
        outputs: Array<AudioDeviceInfo> =
            getSystemService(AudioManager::class.java)
                .getDevices(AudioManager.GET_DEVICES_OUTPUTS),
    ): AudioDeviceInfo? {
        preferredOutputDeviceId?.let { id ->
            outputs.firstOrNull { it.id == id }?.let { return it }
        }
        val name = preferredOutputName ?: return null
        return outputs.firstOrNull {
            it.productName?.toString()?.trim() == name &&
                (preferredOutputType == null || it.type == preferredOutputType)
        }
    }

    private fun isPreferredOutput(device: AudioDeviceInfo): Boolean =
        findPreferredOutput()?.id == device.id

    private fun restoreOutputAfterDeviceChange(changed: List<AudioDeviceInfo>) {
        val preferredName = preferredOutputName
        val preferredId = preferredOutputDeviceId
        if (preferredName == null && preferredId == null) return
        val affectsPreferred = changed.any {
            it.id == preferredId ||
                (preferredName != null &&
                    it.productName?.toString()?.trim() == preferredName)
        }
        if (!affectsPreferred || restoringOutputRoute) return
        synchronized(audioLock) {
            if (restoringOutputRoute) return
            restoringOutputRoute = true
            try {
                if (audioTrack != null) {
                    stopAudioTrack()
                    initializeAudioTrack()
                }
                findPreferredOutput()?.let { device ->
                    if (isBluetoothOutput(device)) {
                        nativeReceiver?.setPreferredOutputDevice(device)
                    }
                }
                Log.i(
                    "SyncAudioOutput",
                    "Output device change handled; preferred=${preferredName ?: preferredId}",
                )
            } catch (error: Exception) {
                Log.w("SyncAudioOutput", "Could not restore output route", error)
            } finally {
                restoringOutputRoute = false
            }
        }
    }

    private fun isBluetoothOutput(device: AudioDeviceInfo): Boolean =
        device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER

    private fun listAudioOutputs(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN,
                ),
                bluetoothPermissionRequestCode,
            )
            return emptyList()
        }
        val manager = getSystemService(AudioManager::class.java)
        Log.i(
            "SyncAudioOutput",
            "AudioManager output devices=${manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).size}"
        )
        val mediaDevices = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            // AudioManager also exposes communication routes (Bluetooth SCO
            // and BLE headset) for the same paired headset. They are not
            // media playback routes and can produce a duplicate row that
            // cannot play AudioTrack music. Keep only media-capable outputs.
            .filter { device ->
                device.type !in setOf(
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLE_HEADSET,
                )
            }
        // Keep one physical route per display name. If Android reports both
        // BLE and A2DP for the same headset, A2DP is preferred because the
        // receiver uses AudioTrack/USAGE_MEDIA.
        val devices = mediaDevices
            .groupBy { it.productName?.toString()?.trim()?.lowercase() ?: "audio output" }
            .values
            .mapNotNull { group ->
                group.maxWithOrNull(
                    compareBy<AudioDeviceInfo> {
                        when (it.type) {
                            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> 3
                            AudioDeviceInfo.TYPE_BLE_SPEAKER -> 2
                            else -> 1
                        }
                    }.thenBy { it.id },
                )
            }
        return devices.map { device ->
            val bluetooth = when (device.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER -> true

                else -> false
            }
            mapOf(
                "id" to device.id.toString(),
                "name" to (device.productName?.toString()?.ifBlank { "Audio output" }
                    ?: "Audio output"),
                "kind" to if (bluetooth) "bluetooth" else "system",
                "isBluetooth" to bluetooth,
                "isSelected" to isPreferredOutput(device),
            )
        }
    }

    private fun stopAudioTrack() {
        synchronized(audioLock) {
            audioTrack?.let { track ->
                try {
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop()
                } catch (_: IllegalStateException) { }
                try { track.flush() } catch (_: IllegalStateException) { }
                try { track.release() } catch (_: IllegalStateException) { }
            }
            audioTrack = null
        }
    }

    private fun latencyDelayMicros(mode: String): Long = when (mode.lowercase()) {
        "ultralow", "ultra_low", "ultra low" -> 60_000L
        "stable" -> 220_000L
        else -> 120_000L
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getSystemService(AudioManager::class.java)
                .unregisterAudioDeviceCallback(audioDeviceCallback)
        }
        nativeSender?.stop()
        pendingNativeSender?.stop()
        nativeReceiver?.stop()
        stopAudioTrack()
        audioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun isEmulator(): Boolean =
        (Build.FINGERPRINT.startsWith("generic") ||
         Build.FINGERPRINT.startsWith("unknown") ||
         Build.MODEL.contains("google_sdk") ||
         Build.MODEL.contains("Emulator") ||
         Build.MODEL.contains("Android SDK built for x86") ||
         Build.MANUFACTURER.contains("Genymotion"))

    companion object {
        var notificationActionSink: EventChannel.EventSink? = null
        var pendingNotificationAction: String? = null

        fun dispatchNotificationAction(action: String) {
            notificationActionSink?.success(action) ?: run {
                pendingNotificationAction = action
            }
        }

        private const val PAIRING_KEY_ALIAS = "sync_audio_pairing_key"
        private const val PAIRING_VALUE_KEY = "pairing_token_v2"
    }
}

private data class MediaNotificationArgs(
    val id: Int,
    val title: String,
    val message: String,
    val isPlaying: Boolean,
    val isMuted: Boolean,
)
