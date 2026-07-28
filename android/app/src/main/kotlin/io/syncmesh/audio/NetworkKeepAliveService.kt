package io.syncmesh.audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.wifi.WifiManager
import android.util.Log

class NetworkKeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "sync_audio:connection",
        ).apply { setReferenceCounted(false) }
        val wifiManager = applicationContext.getSystemService(WifiManager::class.java)
        @Suppress("DEPRECATION")
        wifiLock = wifiManager.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "sync_audio:connection_wifi",
        ).apply { setReferenceCounted(false) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
            "SyncMesh Audio connection",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Keeps active SyncMesh Audio connections available in the background"
                },
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(R.drawable.ic_stat_sync_audio)
            .setContentTitle("SyncMesh Audio")
            .setContentText("Connection is active in the background")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: RuntimeException) {
            // Android can reject foreground-service promotion for background
            // start reasons. This is recoverable and must not crash the app.
            Log.w(TAG, "Network keep-alive foreground service was rejected", error)
            releaseLocks()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (wakeLock?.isHeld != true) wakeLock?.acquire()
        @Suppress("DEPRECATION")
        if (wifiLock?.isHeld != true) wifiLock?.acquire()
        // Do not let Android restart the service after rejected foreground
        // promotion; the next user-initiated connection can start it.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep the foreground service alive if the user swipes the task away.
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        releaseLocks()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun releaseLocks() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wakeLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "NetworkKeepAliveService"
        private const val CHANNEL_ID = "sync_audio_connection"
        private const val NOTIFICATION_ID = 506
    }
}
