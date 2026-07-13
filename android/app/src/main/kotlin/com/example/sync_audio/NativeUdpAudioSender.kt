package com.example.sync_audio

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.TimeUnit

internal class NativeUdpAudioSender(
    private val destinations: List<InetAddress>,
    private val port: Int,
    private val targetDelayMicros: Long,
    private val sessionId: String,
    private val pairingToken: String?,
) {
    private val running = AtomicBoolean(false)
    private val queue = ArrayBlockingQueue<ByteArray>(8)
    private var socket: DatagramSocket? = null
    private var worker: Thread? = null
    private var startNanos = 0L
    private var sequence = 0L
    private var pending = ByteArray(0)
    private var clockSequence = 0L
    private var lastClockSyncMicros = 0L
    private val clockRequests = HashMap<Long, Long>()
    private val syncStates = HashMap<String, SyncState>()
    @Volatile var droppedFrames: Long = 0
        private set

    fun start() {
        if (!running.compareAndSet(false, true)) return
        require(destinations.isNotEmpty()) { "Native sender requires a receiver" }
        socket = DatagramSocket()
        socket?.soTimeout = 1
        startNanos = System.nanoTime()
        SystemAudioPcmBus.nativeSink = { bytes -> onPcm(bytes) }
        worker = Thread({ sendLoop() }, "sync-native-udp-sender").also { it.start() }
    }

    private fun onPcm(bytes: ByteArray) {
        val combined = ByteArray(pending.size + bytes.size)
        pending.copyInto(combined)
        bytes.copyInto(combined, pending.size)
        var offset = 0
        while (combined.size - offset >= FRAME_BYTES) {
            val frame = combined.copyOfRange(offset, offset + FRAME_BYTES)
            if (!queue.offer(frame)) droppedFrames++
            offset += FRAME_BYTES
        }
        pending = combined.copyOfRange(offset, combined.size)
    }

    private fun sendLoop() {
        try {
            while (running.get()) {
                val frame = queue.poll(10, TimeUnit.MILLISECONDS)
                if (frame != null) {
                    val audioSequence = sequence++
                    val timestamp = elapsedMicros() + targetDelayMicros
                    val clear = NativeAudioPacket.encode(
                        type = NativeAudioPacket.TYPE_PCM,
                        sequence = audioSequence,
                        timestampMicros = timestamp,
                        payload = frame,
                    )
                    val wire = if (pairingToken.isNullOrEmpty()) clear else
                        NativeSecureAudioPacket.encrypt(clear, sessionId, pairingToken, audioSequence)
                    destinations.forEach { destination ->
                        socket?.send(DatagramPacket(wire, wire.size, destination, port))
                    }
                }
                val now = elapsedMicros()
                if (now - lastClockSyncMicros >= 2_000_000) {
                    sendClockRequests(now)
                    lastClockSyncMicros = now
                }
                receiveClockResponse()
            }
        } catch (_: InterruptedException) {
            // Normal shutdown.
        } catch (error: Exception) {
            SystemAudioPcmBus.emitError("NATIVE_UDP_SEND_FAILED", error.message ?: "UDP sender failed")
        }
    }

    private fun sendClockRequests(nowMicros: Long) {
        destinations.forEach { destination ->
            val requestSequence = clockSequence++
            clockRequests[requestSequence] = nowMicros
            val request = NativeAudioPacket.encode(
                type = NativeAudioPacket.TYPE_CLOCK_REQUEST,
                sequence = requestSequence,
                timestampMicros = nowMicros,
            )
            socket?.send(DatagramPacket(request, request.size, destination, port))
        }
    }

    private fun receiveClockResponse() {
        val responseBytes = ByteArray(256)
        val datagram = DatagramPacket(responseBytes, responseBytes.size)
        try {
            socket?.receive(datagram)
        } catch (_: SocketTimeoutException) {
            return
        } catch (_: Exception) {
            return
        }
        val response = NativeAudioPacket.decode(datagram.data.copyOf(datagram.length)) ?: return
        if (response.type != NativeAudioPacket.TYPE_CLOCK_RESPONSE) return
        val sentAt = clockRequests.remove(response.sequence) ?: return
        val receivedAt = elapsedMicros()
        val sampleOffset = response.timestampMicros - (sentAt + receivedAt) / 2
        val id = datagram.address.hostAddress ?: return
        val previous = syncStates[id]
        val filtered = if (previous == null) sampleOffset else (previous.offsetMicros * 3 + sampleOffset) / 4
        val drift = if (previous == null) 0 else {
            val elapsed = receivedAt - previous.timestampMicros
            if (elapsed <= 0) 0 else ((filtered - previous.offsetMicros) * 1_000_000 / elapsed).coerceIn(-300, 300)
        }
        syncStates[id] = SyncState(filtered, receivedAt)
        val offsetPacket = NativeAudioPacket.encode(
            type = NativeAudioPacket.TYPE_CLOCK_OFFSET,
            sequence = response.sequence,
            timestampMicros = filtered,
        )
        val driftPacket = NativeAudioPacket.encode(
            type = NativeAudioPacket.TYPE_CLOCK_DRIFT,
            sequence = response.sequence,
            timestampMicros = drift,
        )
        socket?.send(DatagramPacket(offsetPacket, offsetPacket.size, datagram.address, datagram.port))
        socket?.send(DatagramPacket(driftPacket, driftPacket.size, datagram.address, datagram.port))
    }

    fun elapsedMicros(): Long = (System.nanoTime() - startNanos) / 1_000

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        if (SystemAudioPcmBus.nativeSink != null) SystemAudioPcmBus.nativeSink = null
        worker?.interrupt()
        worker = null
        queue.clear()
        socket?.close()
        socket = null
        pending = ByteArray(0)
        clockRequests.clear()
        syncStates.clear()
    }

    companion object {
        private const val FRAME_BYTES = 1_920 // 20 ms, 48 kHz, mono PCM16.
    }

    private data class SyncState(val offsetMicros: Long, val timestampMicros: Long)
}
