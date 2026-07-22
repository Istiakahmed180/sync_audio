import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioEngine: AVAudioEngine?
  private var audioPlayer: AVAudioPlayerNode?
  private let captureBus = 0
  private let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 48000,
    channels: 1,
    interleaved: false
  )!

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupAudioChannels(messenger: engineBridge.applicationRegistrar.messenger())
  }

  // MARK: - Channel Setup

  private func setupAudioChannels(messenger: FlutterBinaryMessenger) {
    setupCaptureChannel(messenger: messenger)
    setupPlaybackChannel(messenger: messenger)
  }

  // MARK: - Audio Capture (Microphone)

  private func setupCaptureChannel(messenger: FlutterBinaryMessenger) {
    let controlChannel = FlutterMethodChannel(
      name: "sync_audio/ios_audio_capture",
      binaryMessenger: messenger
    )
    let streamChannel = FlutterEventChannel(
      name: "sync_audio/ios_audio_stream",
      binaryMessenger: messenger
    )

    let streamHandler = AudioStreamHandler()
    streamChannel.setStreamHandler(streamHandler)

    controlChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.startCapture(streamHandler: streamHandler, result: result)
      case "stop":
        self?.stopCapture(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startCapture(streamHandler: AudioStreamHandler, result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .default,
                              options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)

      let engine = AVAudioEngine()
      audioEngine = engine

      let inputNode = engine.inputNode
      let inputFormat = inputNode.outputFormat(forBus: captureBus)

      inputNode.installTap(onBus: captureBus, bufferSize: 3840, format: inputFormat) {
        [weak streamHandler] buffer, _ in
        guard let channelData = buffer.int16ChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * 2)
        streamHandler?.send(data)
      }

      try engine.start()
      result(nil)
    } catch {
      result(FlutterError(code: "CAPTURE_ERROR",
                          message: error.localizedDescription, details: nil))
    }
  }

  private func stopCapture(result: FlutterResult) {
    audioEngine?.inputNode.removeTap(onBus: captureBus)
    audioEngine?.stop()
    audioEngine = nil
    result(nil)
  }

  // MARK: - Audio Playback

  private func setupPlaybackChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "sync_audio/ios_audio_playback",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "initialize":
        self?.initializePlayback(result: result)
      case "writePcm":
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "INVALID_DATA",
                             message: "Invalid PCM data", details: nil))
          return
        }
        self?.writePcm(data.data, result: result)
      case "stop":
        self?.stopPlayback(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func initializePlayback(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)

      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()
      audioPlayer = player

      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
      try engine.start()

      player.play()
      audioEngine = engine
      result(nil)
    } catch {
      result(FlutterError(code: "PLAYBACK_ERROR",
                          message: error.localizedDescription, details: nil))
    }
  }

  private func writePcm(_ data: Data, result: FlutterResult) {
    guard let player = audioPlayer else {
      result(FlutterError(code: "NOT_INITIALIZED",
                         message: "Player not initialized", details: nil))
      return
    }
    let frameCount = data.count / 2
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: AVAudioFrameCount(frameCount)
    ) else {
      result(FlutterError(code: "BUFFER", message: "Buffer allocation failed", details: nil))
      return
    }
    buffer.frameLength = AVAudioFrameCount(frameCount)

    data.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      buffer.int16ChannelData?[0].assign(
        from: base.assumingMemoryBound(to: Int16.self),
        count: frameCount
      )
    }

    player.scheduleBuffer(buffer, completionHandler: nil)
    result(nil)
  }

  private func stopPlayback(result: FlutterResult) {
    audioPlayer?.stop()
    audioPlayer = nil
    audioEngine?.stop()
    audioEngine = nil
    result(nil)
  }
}

// MARK: - Stream Handler

class AudioStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  func send(_ data: Data) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(FlutterStandardTypedData(bytes: data))
    }
  }
}
