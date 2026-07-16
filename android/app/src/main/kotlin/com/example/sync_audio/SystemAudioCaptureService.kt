package com.example.sync_audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log

class SystemAudioCaptureService : Service() {
    private val audioLock = Any()
    @Volatile
    private var capturing = false
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var mediaProjection: MediaProjection? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand startId=$startId action=${intent?.action}")
        when (intent?.action) {
            ACTION_PREPARE -> {
                // The service is foreground and waiting for the user to grant
                // screen-capture consent. Nothing else to do yet.
                try {
                    promoteToForeground()
                } catch (error: Exception) {
                    Log.e(TAG, "Unable to promote audio capture service", error)
                    SystemAudioPcmBus.emitError(
                        "SYSTEM_AUDIO_START_FAILED",
                        "Unable to promote audio capture to a foreground service: ${error.message}",
                    )
                    stopSelf()
                    return START_NOT_STICKY
                }
                return START_STICKY
            }
            ACTION_START, null -> {
                // Activity.RESULT_OK is -1, so we must use a sentinel other than -1
                // to detect a missing result code.
                var resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, MISSING_RESULT_CODE)
                    ?: MISSING_RESULT_CODE
                // The projection result contains framework-owned binder state. On
                // some Android 13+ builds, the typed Intent getter returns null after
                // the result is forwarded through a service Intent unless the bundle
                // class loader is explicitly initialized. Keep a static fallback
                // populated by MainActivity so the consent Intent is never lost.
                if (resultCode == MISSING_RESULT_CODE) {
                    resultCode = pendingResultCode
                    pendingResultCode = MISSING_RESULT_CODE
                }
                val projectionData = intent?.extras?.let { extras ->
                    extras.classLoader = Intent::class.java.classLoader
                    @Suppress("DEPRECATION")
                    extras.getParcelable(EXTRA_PROJECTION_DATA) as? Intent
                } ?: pendingProjectionData.also { pendingProjectionData = null }
                if (resultCode == MISSING_RESULT_CODE || projectionData == null) {
                    Log.e(
                        TAG,
                        "MediaProjection result data is missing; keys=${intent?.extras?.keySet()}"
                    )
                    SystemAudioPcmBus.emitError(
                        "SYSTEM_AUDIO_START_FAILED",
                        "MediaProjection data is missing"
                    )
                    stopSelf()
                    return START_NOT_STICKY
                }
                try {
                    // The MediaProjection binder validates that this process is
                    // already running as a mediaProjection foreground service.
                    // Do this after consent (the service is only started from
                    // onActivityResult), but before getMediaProjection().
                    promoteToForeground()
                    val projectionManager =
                        getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val projection = projectionManager.getMediaProjection(resultCode, projectionData)
                        ?: error("MediaProjection is unavailable")
                    startCapture(projection)
                    Log.i(TAG, "system audio capture started")
                } catch (error: Exception) {
                    Log.e(TAG, "Unable to start system audio capture", error)
                    SystemAudioPcmBus.emitError(
                        "SYSTEM_AUDIO_START_FAILED",
                        "Unable to start system audio capture: ${error.message}"
                    )
                    stopSelf()
                }
                return START_NOT_STICKY
            }
            else -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }
    }

    private fun promoteToForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun startCapture(projection: MediaProjection) {
        synchronized(audioLock) {
            if (capturing) return
            val captureConfig = AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()
            val sampleRate = 48000
            val frameBytes = sampleRate / 1000 * 20 * 2
            val minBufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            require(minBufferSize > 0) { "Invalid AudioRecord buffer size" }
            val record = AudioRecord.Builder()
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes((minBufferSize * 2).coerceAtLeast(frameBytes * 2))
                .setAudioPlaybackCaptureConfig(captureConfig)
                .build()
            check(record.state == AudioRecord.STATE_INITIALIZED) { "AudioRecord failed to initialize" }
            projection.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopCapture()
                }
            }, null)
            record.startRecording()
            mediaProjection = projection
            audioRecord = record
            capturing = true
            captureThread = Thread({
                val buffer = ByteArray(frameBytes)
                while (capturing) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        SystemAudioPcmBus.emit(buffer.copyOf(read))
                    } else if (read < 0) {
                        SystemAudioPcmBus.emitError(
                            "SYSTEM_AUDIO_READ_FAILED",
                            "System audio read failed"
                        )
                        break
                    }
                }
            }, "sync-system-audio-capture").also { it.start() }
        }
    }

    private fun stopCapture() {
        val record: AudioRecord?
        val projection: MediaProjection?
        synchronized(audioLock) {
            if (!capturing && audioRecord == null && mediaProjection == null) return
            capturing = false
            record = audioRecord
            projection = mediaProjection
            audioRecord = null
            captureThread = null
            mediaProjection = null
        }
        projection?.stop()
        try {
            record?.stop()
        } catch (_: IllegalStateException) {
        }
        record?.release()
    }

    override fun onDestroy() {
        stopCapture()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "System audio capture",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Sync Audio")
                .setContentText("Capturing system audio")
                .setSmallIcon(R.drawable.ic_stat_sync_audio)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Sync Audio")
                .setContentText("Capturing system audio")
                .setSmallIcon(R.drawable.ic_stat_sync_audio)
                .setOngoing(true)
                .build()
        }
    }

    companion object {
        const val ACTION_PREPARE = "sync_audio.action.PREPARE"
        const val ACTION_START = "sync_audio.action.START"
        const val EXTRA_RESULT_CODE = "sync_audio.result_code"
        const val EXTRA_PROJECTION_DATA = "sync_audio.projection_data"
        // Framework-owned MediaProjection data can be lost when forwarded through
        // an Intent extra on some Android 13+ builds. MainActivity populates these
        // just before starting the service as a reliable fallback.
        // Activity.RESULT_OK == -1, so -1 is a valid success code. Use a sentinel
        // to distinguish an unset/missing result code.
        private const val MISSING_RESULT_CODE = -999
        @Volatile
        var pendingResultCode: Int = MISSING_RESULT_CODE
        @Volatile
        var pendingProjectionData: Intent? = null
        private const val CHANNEL_ID = "sync_audio_system_audio"
        private const val NOTIFICATION_ID = 505
        private const val TAG = "SyncAudioCapture"
    }
}
