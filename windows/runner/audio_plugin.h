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
#include <string>
#include <vector>

#pragma comment(lib, "winmm.lib")

class AudioPlugin {
 public:
  explicit AudioPlugin(flutter::BinaryMessenger* messenger);
  ~AudioPlugin();

 private:
  void SetupCaptureChannel(flutter::BinaryMessenger* messenger);
  void SetupPlaybackChannel(flutter::BinaryMessenger* messenger);

  void StartCapture(const flutter::MethodCall<>& call,
                    std::unique_ptr<flutter::MethodResult<>> result);
  void StopCapture(std::unique_ptr<flutter::MethodResult<>> result);
  bool StartWasapiLoopback(std::string* error);
  void CaptureLoop();
  void ReleaseWasapiLoopback();
  void InitializePlayback(std::unique_ptr<flutter::MethodResult<>> result);
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

  // Playback
  HWAVEOUT wave_out_ = nullptr;
  std::atomic<bool> playing_{false};
  std::mutex playback_mutex_;
};

#endif  // RUNNER_AUDIO_PLUGIN_H_
