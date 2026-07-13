package com.example.sync_audio

import java.util.TreeMap
import kotlin.math.abs
import kotlin.math.max

internal data class NativeJitterPacket(
    val sequence: Long,
    val timestampMicros: Long,
    val payload: ByteArray,
    val arrivalMicros: Long,
)

internal class NativeJitterBuffer(
    private var minimumMicros: Long = 80_000,
    private var normalMicros: Long = 120_000,
    private var maximumMicros: Long = 300_000,
) {
    private val packets = TreeMap<Long, NativeJitterPacket>()
    private var nextSequence: Long? = null
    private var lastArrivalMicros: Long? = null
    private var jitterMicros = 0L
    private var missingSinceMicros = 0L
    var underruns = 0L
        private set
    var overruns = 0L
        private set
    var latePackets = 0L
        private set
    var reorders = 0L
        private set

    val size: Int get() = packets.size
    val targetMicros: Long
        get() = (normalMicros + jitterMicros * 2).coerceIn(minimumMicros, maximumMicros)

    @Synchronized
    fun configure(mode: String) {
        when (mode.lowercase()) {
            "ultralow", "ultra_low", "ultra low" -> {
                minimumMicros = 50_000
                normalMicros = 60_000
                maximumMicros = 160_000
            }
            "stable" -> {
                minimumMicros = 160_000
                normalMicros = 220_000
                maximumMicros = 500_000
            }
            else -> {
                minimumMicros = 80_000
                normalMicros = 120_000
                maximumMicros = 300_000
            }
        }
    }

    @Synchronized
    fun add(packet: NativeJitterPacket): Boolean {
        lastArrivalMicros?.let { previous ->
            val deviation = abs(packet.arrivalMicros - previous - 20_000)
            jitterMicros = if (jitterMicros == 0L) deviation else (jitterMicros * 7 + deviation) / 8
        }
        lastArrivalMicros = packet.arrivalMicros
        val next = nextSequence
        if (next != null && isBehind(packet.sequence, next)) {
            latePackets++
            return false
        }
        if (packets.containsKey(packet.sequence)) return false
        if (next != null && packet.sequence != next) reorders++
        packets[packet.sequence] = packet
        while (packets.size > 256) {
            packets.pollFirstEntry()
            overruns++
        }
        return true
    }

    @Synchronized
    fun takeReady(nowMicros: Long): NativeJitterPacket? {
        if (nextSequence == null && packets.isNotEmpty()) nextSequence = packets.firstKey()
        val next = nextSequence ?: return null
        val packet = packets[next]
        if (packet == null) {
            if (packets.isEmpty()) return null
            if (missingSinceMicros == 0L) missingSinceMicros = nowMicros
            if (nowMicros - missingSinceMicros < 30_000) return null
            underruns++
            nextSequence = packets.firstKey()
            missingSinceMicros = 0L
            return null
        }
        missingSinceMicros = 0L
        if (nowMicros < packet.timestampMicros) return null
        packets.remove(next)
        nextSequence = (next + 1) and 0xFFFFFFFFL
        return packet
    }

    @Synchronized
    fun reset() {
        packets.clear()
        nextSequence = null
        lastArrivalMicros = null
        jitterMicros = 0
        missingSinceMicros = 0
        underruns = 0
        overruns = 0
        latePackets = 0
        reorders = 0
    }

    private fun isBehind(sequence: Long, reference: Long): Boolean {
        val difference = (reference - sequence) and 0xFFFFFFFFL
        return difference != 0L && difference < 0x80000000L
    }
}
