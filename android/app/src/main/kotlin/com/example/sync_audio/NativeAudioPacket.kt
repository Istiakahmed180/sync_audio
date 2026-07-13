package com.example.sync_audio

import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class NativeAudioPacket(
    val type: Int,
    val sequence: Long,
    val timestampMicros: Long,
    val codec: Int,
    val payload: ByteArray,
) {
    companion object {
        const val TYPE_PCM = 1
        const val TYPE_CLOCK_REQUEST = 2
        const val TYPE_CLOCK_RESPONSE = 3
        const val TYPE_CLOCK_OFFSET = 4
        const val TYPE_CLOCK_DRIFT = 5
        const val CODEC_PCM16 = 1
        private const val MAGIC = 0x5341
        private const val VERSION = 2
        private const val HEADER_BYTES = 17

        fun encode(
            type: Int,
            sequence: Long,
            timestampMicros: Long,
            payload: ByteArray = ByteArray(0),
            codec: Int = CODEC_PCM16,
        ): ByteArray {
            val result = ByteBuffer.allocate(HEADER_BYTES + payload.size)
                .order(ByteOrder.BIG_ENDIAN)
            result.putShort(MAGIC.toShort())
            result.put(VERSION.toByte())
            result.put(type.toByte())
            result.put(codec.toByte())
            result.putInt(sequence.toInt())
            result.putLong(timestampMicros)
            result.put(payload)
            return result.array()
        }

        fun decode(bytes: ByteArray): NativeAudioPacket? {
            if (bytes.size < HEADER_BYTES) return null
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            if ((buffer.short.toInt() and 0xFFFF) != MAGIC) return null
            if (buffer.get().toInt() != VERSION) return null
            val type = buffer.get().toInt()
            val codec = buffer.get().toInt()
            if (type !in TYPE_PCM..TYPE_CLOCK_DRIFT || codec !in CODEC_PCM16..CODEC_PCM16) {
                return null
            }
            val sequence = buffer.int.toLong() and 0xFFFFFFFFL
            val timestamp = buffer.long
            val payload = ByteArray(buffer.remaining())
            buffer.get(payload)
            return NativeAudioPacket(type, sequence, timestamp, codec, payload)
        }
    }
}
