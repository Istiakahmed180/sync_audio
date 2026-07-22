package com.example.sync_audio

import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.util.Log
import android.media.AudioTrack
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

internal class NativeUdpAudioReceiver(
    private val port: Int,
    private val latencyMode: String,
    private val sessionId: String?,
    private val pairingToken: String?,
    private val audioManager: AudioManager,
) {
    private val running = AtomicBoolean(false)
    private val jitter = NativeJitterBuffer()
    private var socket: DatagramSocket? = null
    private var receiveThread: Thread? = null
    private var playbackThread: Thread? = null
    private var audioTrack: AudioTrack? = null
    @Volatile private var preferredOutputDeviceId: Int? = null
    private var receiverStartNanos = 0L
    @Volatile private var hostToLocalOffsetMicros = 0L
    @Volatile private var clockOffsetInitialized = false
    @Volatile private var driftPpm = 0L
    @Volatile private var driftUpdateMicros = 0L
    @Volatile var lastError: String? = null
        private set

    fun start() {
        if (!running.compareAndSet(false, true)) return
        jitter.configure(latencyMode)
        receiverStartNanos = System.nanoTime()
        audioTrack = createAudioTrack()
        socket = DatagramSocket(port)
        audioTrack?.play()
        audioTrack?.let { track ->
            preferredOutputDeviceId?.let { id ->
                audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .firstOrNull { it.id == id }
                    ?.let { device ->
                        val applied = track.setPreferredDevice(device)
                        Log.i(TAG, "Preferred audio output ${device.productName} (${device.id}) applied=$applied")
                    }
            }
        }
        receiveThread = Thread({ receiveLoop() }, "sync-native-udp-receiver").also { it.start() }
        playbackThread = Thread({ playbackLoop() }, "sync-native-audiotrack").also { it.start() }
    }

    fun setPreferredOutputDevice(device: AudioDeviceInfo): Boolean {
        preferredOutputDeviceId = device.id
        return audioTrack?.setPreferredDevice(device) ?: true
    }

    private fun receiveLoop() {
        val buffer = ByteArray(65_535)
        try {
            while (running.get()) {
                val datagram = DatagramPacket(buffer, buffer.size)
                socket?.receive(datagram)
                var bytes = datagram.data.copyOf(datagram.length)
                if (bytes.size >= 3 && bytes[0] == 0x53.toByte() && bytes[1] == 0x45.toByte()) {
                    val token = pairingToken
                    val session = sessionId
                    if (token == null || session == null) continue
                    bytes = NativeSecureAudioPacket.decrypt(bytes, session, token) ?: continue
                }
                val packet = NativeAudioPacket.decode(bytes) ?: continue
                when (packet.type) {
                    NativeAudioPacket.TYPE_CLOCK_REQUEST -> sendClockResponse(packet.sequence, datagram.address, datagram.port)
                    NativeAudioPacket.TYPE_CLOCK_OFFSET -> {
                        hostToLocalOffsetMicros = packet.timestampMicros
                        driftUpdateMicros = nowMicros()
                        clockOffsetInitialized = true
                    }
                    NativeAudioPacket.TYPE_CLOCK_DRIFT -> driftPpm = packet.timestampMicros.coerceIn(-300, 300)
                    NativeAudioPacket.TYPE_PCM -> {
                        if (packet.codec != NativeAudioPacket.CODEC_PCM16) continue
                        val now = nowMicros()
                        if (!clockOffsetInitialized) {
                            // Native-only sessions do not have the Dart clock
                            // exchange. Bootstrap from the first packet, then
                            // keep the configured target delay ahead of arrival.
                            hostToLocalOffsetMicros = now - packet.timestampMicros + jitter.targetMicros
                            driftUpdateMicros = now
                            clockOffsetInitialized = true
                        }
                        val correction = ((now - driftUpdateMicros) * driftPpm) / 1_000_000
                        jitter.add(
                            NativeJitterPacket(
                                sequence = packet.sequence,
                                timestampMicros = packet.timestampMicros + hostToLocalOffsetMicros + correction,
                                payload = packet.payload,
                                arrivalMicros = now,
                            ),
                        )
                    }
                }
            }
        } catch (error: Exception) {
            if (running.get()) fail(error.message ?: "UDP receiver failed")
        }
    }

    private fun playbackLoop() {
        try {
            while (running.get()) {
                val packet = jitter.takeReady(nowMicros())
                if (packet == null) {
                    Thread.sleep(2)
                    continue
                }
                audioTrack?.write(packet.payload, 0, packet.payload.size, AudioTrack.WRITE_BLOCKING)
            }
        } catch (error: Exception) {
            if (running.get()) fail(error.message ?: "AudioTrack playback failed")
        }
    }

    private fun sendClockResponse(sequence: Long, address: InetAddress, port: Int) {
        val response = NativeAudioPacket.encode(
            type = NativeAudioPacket.TYPE_CLOCK_RESPONSE,
            sequence = sequence,
            timestampMicros = nowMicros(),
        )
        socket?.send(DatagramPacket(response, response.size, address, port))
    }

    private fun createAudioTrack(): AudioTrack {
        val sampleRate = 48_000
        val bluetoothRoute = currentBluetoothOutput() != null
        val minimum = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        if (!bluetoothRoute) attributes.setFlags(AudioAttributes.FLAG_LOW_LATENCY)
        val bufferDurationMs = if (bluetoothRoute) 120 else 20
        val bufferBytes = sampleRate / 1000 * bufferDurationMs * 2
        val builder = AudioTrack.Builder()
            .setAudioAttributes(attributes.build())
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(minimum.coerceAtLeast(bufferBytes))
            .setTransferMode(AudioTrack.MODE_STREAM)
        if (!bluetoothRoute) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        val track = builder.build()
            .also { check(it.state == AudioTrack.STATE_INITIALIZED) { "Native AudioTrack initialization failed" } }
        preferredOutputDeviceId?.let { id ->
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.id == id }
                ?.let { track.setPreferredDevice(it) }
        }
        return track
    }

    private fun currentBluetoothOutput(): AudioDeviceInfo? {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        preferredOutputDeviceId?.let { id ->
            outputs.firstOrNull { it.id == id && isBluetoothOutput(it) }?.let { return it }
        }
        return outputs.firstOrNull(::isBluetoothOutput)
    }

    private fun isBluetoothOutput(device: AudioDeviceInfo): Boolean =
        device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
            device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER

    private fun nowMicros(): Long = (System.nanoTime() - receiverStartNanos) / 1_000

    private fun fail(message: String) {
        lastError = message
        SystemAudioPcmBus.emitError("NATIVE_UDP_RECEIVE_FAILED", message)
        stop()
    }

    companion object {
        private const val TAG = "SyncAudioReceiver"
    }

    fun diagnostics(): Map<String, Any> = mapOf(
        "path" to "native_pcm",
        "bufferPackets" to jitter.size,
        "targetBufferMicros" to jitter.targetMicros,
        "underruns" to jitter.underruns,
        "overruns" to jitter.overruns,
        "packetLossPercent" to jitter.packetLossPercent,
        "receivedPackets" to jitter.receivedPackets,
        "lostPackets" to jitter.lostPackets,
        "latePackets" to jitter.latePackets,
        "reorders" to jitter.reorders,
        "driftPpm" to driftPpm,
    )

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        receiveThread?.interrupt()
        playbackThread?.interrupt()
        receiveThread = null
        playbackThread = null
        socket?.close()
        socket = null
        audioTrack?.let {
            try { it.stop() } catch (_: IllegalStateException) { }
            it.flush()
            it.release()
        }
        audioTrack = null
        jitter.reset()
        clockOffsetInitialized = false
    }
}
