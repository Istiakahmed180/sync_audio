package com.example.sync_audio

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object SystemAudioPcmBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    var sink: EventChannel.EventSink? = null
    @Volatile var nativeSink: ((ByteArray) -> Unit)? = null

    fun emit(bytes: ByteArray) {
        nativeSink?.invoke(bytes)
        mainHandler.post { sink?.success(bytes) }
    }

    fun emitError(code: String, message: String) {
        mainHandler.post { sink?.error(code, message, null) }
    }
}
