import Cocoa
import FlutterMacOS
import AVFoundation
import ScreenCaptureKit
import AudioToolbox

@main
class AppDelegate: FlutterAppDelegate {
  private var audioEngine: AVAudioEngine?
  private var blackHoleCapture: MacosBlackHoleCapture?
  private var systemAudioCapture: AnyObject?
  private var audioPlayer: AVAudioPlayerNode?
  private let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 48000,
    channels: 1,
    interleaved: false
  )!

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    setupCaptureChannel(messenger: controller.engine.binaryMessenger)
    setupPlaybackChannel(messenger: controller.engine.binaryMessenger)
    setupAudioOutputChannel(messenger: controller.engine.binaryMessenger)
  }

  private func setupAudioOutputChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "sync_audio/audio_output",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "APP_UNAVAILABLE", message: "Audio output service is unavailable", details: nil))
        return
      }
      if call.method == "listOutputs" {
        result(self.listAudioOutputs())
        return
      }
      if call.method == "selectOutput",
         let id = call.arguments as? String,
         let deviceId = AudioDeviceID(id) {
        result(self.selectAudioOutput(deviceId) ? nil : FlutterError(
          code: "OUTPUT_SELECT_FAILED",
          message: "Could not select the audio output",
          details: nil
        ))
        return
      }
      guard call.method == "openOutputSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
      NSWorkspace.shared.open(url)
      result(nil)
    }
  }

  private func listAudioOutputs() -> [[String: Any]] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    ) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    var dataSize = size
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      &dataSize, &devices
    ) == noErr else { return [] }

    let selected = defaultOutputDevice()
    return devices.map { device in
      let name = audioDeviceName(device)
      let transport = audioDeviceTransport(device)
      let bluetooth = transport == kAudioDeviceTransportTypeBluetooth ||
        transport == kAudioDeviceTransportTypeBluetoothLE ||
        name.localizedCaseInsensitiveContains("bluetooth")
      return [
        "id": String(device),
        "name": name,
        "kind": bluetooth ? "bluetooth" : "system",
        "isBluetooth": bluetooth,
        "isSelected": device == selected,
      ]
    }
  }

  private func audioDeviceName(_ device: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
          let name else { return "Audio output" }
    return name.takeUnretainedValue() as String
  }

  private func audioDeviceTransport(_ device: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
    return transport
  }

  private func defaultOutputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      &size, &device
    )
    return device
  }

  private func selectAudioOutput(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var selected = device
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
      size, &selected
    ) == noErr
  }

  // MARK: - Audio Capture (Microphone / System Input)

  private func setupCaptureChannel(messenger: FlutterBinaryMessenger) {
    let controlChannel = FlutterMethodChannel(
      name: "sync_audio/macos_audio_capture",
      binaryMessenger: messenger
    )
    let streamChannel = FlutterEventChannel(
      name: "sync_audio/macos_audio_stream",
      binaryMessenger: messenger
    )

    let streamHandler = MacosAudioStreamHandler()
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

  private func startCapture(streamHandler: MacosAudioStreamHandler, result: @escaping FlutterResult) {
    if let blackHole = MacosBlackHoleCapture() {
      blackHoleCapture = blackHole
      blackHole.start { [weak streamHandler] data in
        streamHandler?.send(data)
      } completion: { [weak self] error in
        if let error {
          self?.blackHoleCapture = nil
          result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
      return
    }

    if #available(macOS 13.0, *) {
      let capture = MacosSystemAudioCapture()
      systemAudioCapture = capture
      capture.start { [weak self, weak streamHandler] error in
        if let error {
          self?.systemAudioCapture = nil
          result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
        } else {
          streamHandler?.setActive(true)
          result(nil)
        }
      } onAudio: { [weak streamHandler] data in
        streamHandler?.send(data)
      }
      return
    }

    let engine = AVAudioEngine()
    audioEngine = engine

    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    inputNode.installTap(onBus: 0, bufferSize: 3840, format: inputFormat) {
      [weak streamHandler] buffer, _ in
      let frameLength = Int(buffer.frameLength)
      var samples = [Int16](repeating: 0, count: frameLength)
      if let channelData = buffer.int16ChannelData {
        for index in 0..<frameLength { samples[index] = channelData[0][index] }
      } else if let channelData = buffer.floatChannelData {
        for index in 0..<frameLength {
          let value = max(-1.0, min(1.0, channelData[0][index]))
          samples[index] = Int16(value * Float(Int16.max))
        }
      } else {
        return
      }
      let data = samples.withUnsafeBytes { Data($0) }
      streamHandler?.send(data)
    }

    do {
      try engine.start()
      result(nil)
    } catch {
      result(FlutterError(code: "CAPTURE_ERROR",
                          message: error.localizedDescription, details: nil))
    }
  }

  private func stopCapture(result: FlutterResult) {
    blackHoleCapture?.stop()
    blackHoleCapture = nil
    if #available(macOS 13.0, *) {
      (systemAudioCapture as? MacosSystemAudioCapture)?.stop()
    }
    systemAudioCapture = nil
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    audioEngine = nil
    result(nil)
  }

  // MARK: - Audio Playback

  private func setupPlaybackChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "sync_audio/macos_audio_playback",
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
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    audioPlayer = player

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

    do {
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
      buffer.int16ChannelData?[0].update(
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

private final class MacosBlackHoleCapture {
  private let engine = AVAudioEngine()

  init?() {
    guard let deviceID = Self.findDevice(named: "BlackHole") else { return nil }
    var mutableDeviceID = deviceID
    guard let audioUnit = engine.inputNode.audioUnit,
          AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
          ) == noErr else { return nil }
  }

  func start(onAudio: @escaping (Data) -> Void, completion: @escaping (Error?) -> Void) {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    // 960 mono frames = 20 ms at 48 kHz = 1920 PCM bytes, matching the
    // Android/native packet size and staying below the Wi-Fi MTU.
    input.installTap(onBus: 0, bufferSize: 960, format: format) { buffer, _ in
      let frames = Int(buffer.frameLength)
      let channels = max(Int(buffer.format.channelCount), 1)
      var samples = [Int16](repeating: 0, count: frames)
      if let floatData = buffer.floatChannelData {
        for frame in 0..<frames {
          var value: Float = 0
          for channel in 0..<channels { value += floatData[channel][frame] }
          value = max(-1, min(1, value / Float(channels)))
          samples[frame] = Int16(value * Float(Int16.max))
        }
      } else if let intData = buffer.int16ChannelData {
        for frame in 0..<frames {
          var value = 0
          for channel in 0..<channels { value += Int(intData[channel][frame]) }
          samples[frame] = Int16(value / channels)
        }
      } else {
        return
      }
      onAudio(samples.withUnsafeBytes { Data($0) })
    }
    do {
      try engine.start()
      completion(nil)
    } catch {
      input.removeTap(onBus: 0)
      completion(error)
    }
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
  }

  private static func findDevice(named name: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
    for device in devices {
      var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      var deviceName: Unmanaged<CFString>?
      var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      guard AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &deviceName) == noErr,
            let deviceName else { continue }
      if String(deviceName.takeUnretainedValue()).localizedCaseInsensitiveContains(name) { return device }
    }
    return nil
  }
}

class MacosAudioStreamHandler: NSObject, FlutterStreamHandler {
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

  func setActive(_ active: Bool) {
    // Kept as a hook for stream lifecycle notifications. The event channel
    // itself remains the source of PCM data for Flutter.
  }
}

@available(macOS 13.0, *)
private final class MacosSystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
  private let queue = DispatchQueue(label: "sync_audio.macos.system-audio")
  private var stream: SCStream?
  private var audioHandler: ((Data) -> Void)?
  private var completion: ((Error?) -> Void)?

  func start(completion: @escaping (Error?) -> Void, onAudio: @escaping (Data) -> Void) {
    self.completion = completion
    self.audioHandler = onAudio
    Task { [weak self] in
      guard let self else { return }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
      guard let display = content.displays.first else {
        completion(NSError(domain: "SyncAudio", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No display is available for system audio capture."]))
        return
      }
      let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
      let configuration = SCStreamConfiguration()
      configuration.capturesAudio = true
      configuration.excludesCurrentProcessAudio = true
      configuration.sampleRate = 48_000
      configuration.channelCount = 1
      configuration.width = 2
      configuration.height = 2
      let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
      self.stream = stream
      do {
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
      } catch {
        completion(error)
        return
      }
      Task {
        do {
          try await stream.startCapture()
          completion(nil)
        } catch {
          completion(error)
        }
      }
      } catch {
        completion(error)
      }
    }
  }

  func stop() {
    stream?.stopCapture()
    stream = nil
    audioHandler = nil
    completion = nil
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
              of type: SCStreamOutputType) {
    guard type == .audio, let data = pcm16Data(from: sampleBuffer) else { return }
    audioHandler?(data)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.completion?(error)
      self?.completion = nil
    }
  }

  private func pcm16Data(from sampleBuffer: CMSampleBuffer) -> Data? {
    guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return nil }
    let asbd = asbdPointer.pointee
    let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
    let channels = max(Int(asbd.mChannelsPerFrame), 1)
    let bytesPerSample = Int(asbd.mBytesPerFrame) / channels
    guard bytesPerSample == 2 || bytesPerSample == 4 else { return nil }

    let maxBuffers = max(channels, 8)
    let listSize = MemoryLayout<AudioBufferList>.size +
      (maxBuffers - 1) * MemoryLayout<AudioBuffer>.size
    let listStorage = UnsafeMutableRawPointer.allocate(
      byteCount: listSize,
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { listStorage.deallocate() }
    let list = listStorage.assumingMemoryBound(to: AudioBufferList.self)
    var retainedBlockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: list,
      bufferListSize: listSize,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: 0,
      blockBufferOut: &retainedBlockBuffer
    )
    guard status == noErr else { return nil }

    let buffers = UnsafeMutableAudioBufferListPointer(list)
    guard !buffers.isEmpty else { return nil }
    var output = [Int16](repeating: 0, count: frameCount)
    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    for frame in 0..<frameCount {
      var sample = 0.0
      var sampleChannels = 0
      for audioBuffer in buffers {
        guard let data = audioBuffer.mData else { continue }
        let bufferChannels = max(Int(audioBuffer.mNumberChannels), 1)
        for channel in 0..<bufferChannels {
          let offset = (frame * bufferChannels + channel) * bytesPerSample
          if isFloat {
            sample += Double(UnsafeRawPointer(data).load(fromByteOffset: offset, as: Float.self))
          } else {
            sample += Double(UnsafeRawPointer(data).load(fromByteOffset: offset, as: Int16.self)) / Double(Int16.max)
          }
          sampleChannels += 1
        }
      }
      let normalized = max(-1.0, min(1.0, sample / Double(max(sampleChannels, 1))))
      output[frame] = Int16(normalized * Double(Int16.max))
    }
    return output.withUnsafeBytes { Data($0) }
  }
}
