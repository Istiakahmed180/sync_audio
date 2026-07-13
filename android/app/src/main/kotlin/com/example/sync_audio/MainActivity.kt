package com.example.sync_audio

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "sync_audio/audio_track"
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val audioLock = Any()
    private var audioTrack: AudioTrack? = null
    private val recordChannelName = "sync_audio/audio_record"
    private val recordStreamChannelName = "sync_audio/audio_record_stream"
    private val microphonePermissionRequestCode = 7001
    private var audioEventSink: EventChannel.EventSink? = null
    @Volatile private var audioRecording = false
    private var audioRecord: AudioRecord? = null
    private var audioRecordThread: Thread? = null
    private var pendingAudioStartResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        try {
                            initializeAudioTrack()
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("AUDIO_INIT_FAILED", "Unable to initialize AudioTrack", null)
                        }
                    }
                    "writePcm" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data == null) {
                            result.error("INVALID_PCM", "PCM data is missing", null)
                            return@setMethodCallHandler
                        }
                        audioExecutor.execute {
                            val written = synchronized(audioLock) {
                                audioTrack?.write(data, 0, data.size, AudioTrack.WRITE_BLOCKING) ?: -1
                            }
                            runOnUiThread { result.success(written) }
                        }
                    }
                    "stop" -> {
                        stopAudioTrack()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, recordStreamChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                    stopAudioRecord()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, recordChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startMicrophoneCapture(result)
                    "stop" -> {
                        stopAudioRecord()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startMicrophoneCapture(result: MethodChannel.Result) {
        if (audioRecording) {
            result.success(null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingAudioStartResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphonePermissionRequestCode)
            return
        }
        try {
            startAudioRecord()
            result.success(null)
        } catch (_: Exception) {
            result.error("AUDIO_RECORD_INIT_FAILED", "Unable to initialize microphone capture", null)
        }
    }

    private fun startAudioRecord() {
        synchronized(audioLock) {
            if (audioRecording) return
            val sampleRate = 44100
            val minBufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            require(minBufferSize > 0) { "Invalid AudioRecord buffer size" }
            val record = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                (minBufferSize * 2).coerceAtLeast(4096),
            )
            check(record.state == AudioRecord.STATE_INITIALIZED) { "AudioRecord failed to initialize" }
            record.startRecording()
            audioRecord = record
            audioRecording = true
            audioRecordThread = Thread({
                val buffer = ByteArray(2048)
                while (audioRecording) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        val chunk = buffer.copyOf(read)
                        runOnUiThread {
                            if (audioRecording) audioEventSink?.success(chunk)
                        }
                    } else if (read < 0) {
                        runOnUiThread {
                            audioEventSink?.error("AUDIO_READ_FAILED", "Microphone read failed", null)
                        }
                        break
                    }
                }
            }, "sync-audio-record").also { it.start() }
        }
    }

    private fun stopAudioRecord() {
        val record: AudioRecord?
        synchronized(audioLock) {
            audioRecording = false
            record = audioRecord
            audioRecord = null
            audioRecordThread = null
        }
        try {
            record?.stop()
        } catch (_: IllegalStateException) {
        }
        record?.release()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != microphonePermissionRequestCode) return
        val result = pendingAudioStartResult
        pendingAudioStartResult = null
        if (result == null) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            try {
                startAudioRecord()
                result.success(null)
            } catch (_: Exception) {
                result.error("AUDIO_RECORD_INIT_FAILED", "Unable to initialize microphone capture", null)
            }
        } else {
            result.error("MICROPHONE_PERMISSION_DENIED", "Microphone permission was denied", null)
        }
    }

    private fun initializeAudioTrack() {
        synchronized(audioLock) {
            if (audioTrack != null) return
            val sampleRate = 44100
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes((minBufferSize.coerceAtLeast(4096)) * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            audioTrack?.play()
        }
    }

    private fun stopAudioTrack() {
        synchronized(audioLock) {
            audioTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop()
                track.flush()
                track.release()
            }
            audioTrack = null
        }
    }

    override fun onDestroy() {
        stopAudioRecord()
        stopAudioTrack()
        audioExecutor.shutdownNow()
        super.onDestroy()
    }
}
