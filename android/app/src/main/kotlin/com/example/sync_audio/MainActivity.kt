package com.example.sync_audio

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
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.os.Build
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                            val selected = synchronized(audioLock) {
                                val flutterSelected = audioTrack?.let {
                                    device != null && it.setPreferredDevice(device)
                                } ?: true
                                val nativeSelected = nativeReceiver?.let {
                                    device != null && it.setPreferredOutputDevice(device)
                                } ?: true
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

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_audio/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        val title = call.argument<String>("title") ?: "Sync Audio"
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
                            title = call.argument<String>("title") ?: "Sync Audio",
                            message = call.argument<String>("message") ?: "Sync Audio",
                            isPlaying = call.argument<Boolean>("isPlaying") ?: false,
                            isMuted = call.argument<Boolean>("isMuted") ?: false,
                        )
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
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
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
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
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
                            nativeReceiver = NativeUdpAudioReceiver(
                                port = port,
                                latencyMode = mode,
                                sessionId = sessionId,
                                pairingToken = pairingToken,
                                codec = nativeCodec,
                                audioManager = getSystemService(AudioManager::class.java),
                            ).also { it.start() }
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
                        nativeReceiver?.diagnostics() ?: mapOf("path" to "dart_fallback"),
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
                            val written = synchronized(audioLock) {
                                audioTrack?.write(data, 0, data.size, AudioTrack.WRITE_BLOCKING)
                                    ?: -1
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
                "Sync Audio status",
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
                    "Sync Audio controls",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Start, stop, mute and volume controls for Sync Audio"
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
            .setAction("com.tdevs.sync_audio.NOTIFICATION_$action")
        val pending = PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, label, pending).build()
    }

    private fun initializeAudioTrack() {
        synchronized(audioLock) {
            if (audioTrack != null) return
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
            preferredOutputDeviceId?.let { id ->
                getSystemService(AudioManager::class.java)
                    .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .firstOrNull { it.id == id }
                    ?.let { audioTrack?.setPreferredDevice(it) }
            }
            audioTrack?.play()
            preferredOutputDeviceId?.let { id ->
                getSystemService(AudioManager::class.java)
                    .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .firstOrNull { it.id == id }
                    ?.let { device ->
                        val applied = audioTrack?.setPreferredDevice(device)
                        Log.i(
                            "SyncAudioOutput",
                            "Preferred output ${device.productName} (${device.id}) applied=$applied"
                        )
                    }
            }
        }
    }

    private fun currentBluetoothOutput(audioManager: AudioManager): AudioDeviceInfo? {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        preferredOutputDeviceId?.let { id ->
            outputs.firstOrNull { it.id == id && isBluetoothOutput(it) }?.let { return it }
        }
        return outputs.firstOrNull(::isBluetoothOutput)
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
                "isSelected" to (preferredOutputDeviceId == device.id),
            )
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

    private fun latencyDelayMicros(mode: String): Long = when (mode.lowercase()) {
        "ultralow", "ultra_low", "ultra low" -> 60_000L
        "stable" -> 220_000L
        else -> 120_000L
    }

    override fun onDestroy() {
        nativeSender?.stop()
        pendingNativeSender?.stop()
        nativeReceiver?.stop()
        stopAudioTrack()
        audioExecutor.shutdownNow()
        super.onDestroy()
    }

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
