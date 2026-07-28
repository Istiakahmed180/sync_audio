package io.syncmesh.audio

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object SystemAudioPcmBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    var sink: EventChannel.EventSink? = null
    @Volatile var nativeSink: ((ByteArray) -> Unit)? = null

    fun emit(bytes: ByteArray) {
        val nativeHandler = nativeSink
        nativeHandler?.invoke(bytes)

        // Native host streaming consumes PCM directly. Do not also enqueue
        // every 20 ms audio frame on Flutter's main thread; that queue can
        // grow under load and contribute to an Android ANR.
        if (nativeHandler == null) {
            mainHandler.post { sink?.success(bytes) }
        }
    }

    fun emitError(code: String, message: String) {
        mainHandler.post { sink?.error(code, message, null) }
    }
}
