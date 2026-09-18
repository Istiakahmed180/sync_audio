#ifndef RUNNER_AUDIO_PLUGIN_H_
#define RUNNER_AUDIO_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <Windows.h>
#include <mmsystem.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <ksmedia.h>
#include <memory>
#include <mutex>
#include <thread>
#include <atomic>
#include <condition_variable>
#include <string>
#include <vector>

#pragma comment(lib, "winmm.lib")

class AudioPlugin {
 public:
  // |host_window| is the top-level window used to marshal audio buffers onto
  // the platform thread before they are sent to Flutter.
  AudioPlugin(flutter::BinaryMessenger* messenger, HWND host_window);
  ~AudioPlugin();

  // Drains PCM captured on the audio thread and forwards it to Flutter. Only
  // call this from the platform thread.
  void DrainPendingCapture();

  // Posted from the audio thread when captured PCM is ready to be delivered.
  static constexpr UINT kCaptureDataMessage = WM_APP + 1;

 private:
  void SetupCaptureChannel(flutter::BinaryMessenger* messenger);
  void SetupPlaybackChannel(flutter::BinaryMessenger* messenger);
  void SetupDeviceInfoChannel(flutter::BinaryMessenger* messenger);
  void SetupNetworkInfoChannel(flutter::BinaryMessenger* messenger);

  void StartCapture(const flutter::MethodCall<>& call,
                    std::unique_ptr<flutter::MethodResult<>> result);
  void StopCapture(std::unique_ptr<flutter::MethodResult<>> result);
  bool StartWasapiLoopback(std::string* error);
  void CaptureLoop();
  void ReleaseWasapiLoopback();
  void InitializePlayback(std::unique_ptr<flutter::MethodResult<>> result);
  void PlaybackLoop();
  void WritePcm(const flutter::MethodCall<>& call,
                std::unique_ptr<flutter::MethodResult<>> result);
  void StopPlayback(std::unique_ptr<flutter::MethodResult<>> result);

  // Capture
  IMMDevice* capture_device_ = nullptr;
  IAudioClient* capture_client_ = nullptr;
  IAudioCaptureClient* capture_reader_ = nullptr;
  WAVEFORMATEX* capture_format_ = nullptr;
  HANDLE capture_event_ = nullptr;
  std::thread capture_thread_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> capture_sink_;
  std::atomic<bool> capturing_{false};
  HWND host_window_ = nullptr;
  std::mutex capture_queue_mutex_;
  std::vector<std::vector<uint8_t>> capture_queue_;
  std::atomic<bool> capture_message_posted_{false};

  // Playback
  HWAVEOUT wave_out_ = nullptr;
  UINT playback_device_id_ = WAVE_MAPPER;
  std::atomic<bool> playing_{false};
  std::mutex playback_mutex_;
  std::thread playback_thread_;
  std::mutex playback_buffer_mutex_;
  std::condition_variable playback_cv_;
  std::vector<std::vector<uint8_t>> playback_buffers_;
};

#endif  // RUNNER_AUDIO_PLUGIN_H_
