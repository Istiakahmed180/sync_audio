package com.example.sync_audio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action?.substringAfter("NOTIFICATION_") ?: return
        MainActivity.dispatchNotificationAction(action)
    }
}
