package com.example.sync_audio

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object SystemAudioPcmBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    var sink: EventChannel.EventSink? = null

    fun emit(bytes: ByteArray) {
        mainHandler.post { sink?.success(bytes) }
    }

    fun emitError(code: String, message: String) {
        mainHandler.post { sink?.error(code, message, null) }
    }
}
