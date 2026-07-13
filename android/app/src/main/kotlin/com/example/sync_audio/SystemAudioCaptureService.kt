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

class SystemAudioCaptureService : Service() {
    private val audioLock = Any()
    @Volatile private var capturing = false
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var mediaProjection: MediaProjection? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, -1) ?: -1
        val projectionData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_PROJECTION_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_PROJECTION_DATA)
        }
        if (resultCode < 0 || projectionData == null) {
            SystemAudioPcmBus.emitError("SYSTEM_AUDIO_START_FAILED", "MediaProjection data is missing")
            stopSelf()
            return START_NOT_STICKY
        }

        try {
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
            startCapture(resultCode, projectionData)
        } catch (_: Exception) {
            SystemAudioPcmBus.emitError("SYSTEM_AUDIO_START_FAILED", "Unable to start system audio capture")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startCapture(resultCode: Int, projectionData: Intent) {
        synchronized(audioLock) {
            if (capturing) return
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = projectionManager.getMediaProjection(resultCode, projectionData)
                ?: error("MediaProjection is unavailable")
            val captureConfig = AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .build()
            val sampleRate = 44100
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
                .setBufferSizeInBytes((minBufferSize * 2).coerceAtLeast(8192))
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
                val buffer = ByteArray(4096)
                while (capturing) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        SystemAudioPcmBus.emit(buffer.copyOf(read))
                    } else if (read < 0) {
                        SystemAudioPcmBus.emitError("SYSTEM_AUDIO_READ_FAILED", "System audio read failed")
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
                .setSmallIcon(applicationInfo.icon)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Sync Audio")
                .setContentText("Capturing system audio")
                .setSmallIcon(applicationInfo.icon)
                .setOngoing(true)
                .build()
        }
    }

    companion object {
        const val EXTRA_RESULT_CODE = "sync_audio.result_code"
        const val EXTRA_PROJECTION_DATA = "sync_audio.projection_data"
        private const val CHANNEL_ID = "sync_audio_system_audio"
        private const val NOTIFICATION_ID = 505
    }
}
