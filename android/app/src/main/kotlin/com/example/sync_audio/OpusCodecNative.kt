package com.example.sync_audio

internal object OpusCodecNative {
    private var loaded = false

    init {
        try {
            // libopus is packaged by opus_codec_android; the bridge calls its
            // public C API without duplicating the codec in this app.
            System.loadLibrary("opus")
            System.loadLibrary("sync_audio_opus")
            loaded = nativeAvailable()
        } catch (_: UnsatisfiedLinkError) {
            loaded = false
        }
    }

    fun isAvailable(): Boolean = loaded

    fun createEncoder(sampleRate: Int = 48_000, channels: Int = 1): Long =
        if (loaded) nativeCreateEncoder(sampleRate, channels) else 0

    fun encode(handle: Long, pcm: ByteArray): ByteArray? {
        if (!loaded || handle == 0L) return null
        val output = ByteArray(4_000)
        val length = nativeEncode(handle, pcm, output)
        return if (length > 0) output.copyOf(length) else null
    }

    fun destroyEncoder(handle: Long) {
        if (loaded && handle != 0L) nativeDestroyEncoder(handle)
    }

    fun createDecoder(sampleRate: Int = 48_000, channels: Int = 1): Long =
        if (loaded) nativeCreateDecoder(sampleRate, channels) else 0

    fun decode(handle: Long, encoded: ByteArray): ByteArray? {
        if (!loaded || handle == 0L) return null
        val output = ByteArray(1_920)
        val length = nativeDecode(handle, encoded, output)
        return if (length > 0) output.copyOf(length) else null
    }

    fun destroyDecoder(handle: Long) {
        if (loaded && handle != 0L) nativeDestroyDecoder(handle)
    }

    private external fun nativeAvailable(): Boolean
    private external fun nativeCreateEncoder(sampleRate: Int, channels: Int): Long
    private external fun nativeEncode(handle: Long, pcm: ByteArray, output: ByteArray): Int
    private external fun nativeDestroyEncoder(handle: Long)
    private external fun nativeCreateDecoder(sampleRate: Int, channels: Int): Long
    private external fun nativeDecode(handle: Long, encoded: ByteArray, pcm: ByteArray): Int
    private external fun nativeDestroyDecoder(handle: Long)
}
