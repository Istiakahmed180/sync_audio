#ifndef RUNNER_AUDIO_PLUGIN_H_
#define RUNNER_AUDIO_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <Windows.h>
#include <mmsystem.h>
#include <memory>
#include <mutex>
#include <thread>
#include <atomic>
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
  void InitializePlayback(std::unique_ptr<flutter::MethodResult<>> result);
  void WritePcm(const flutter::MethodCall<>& call,
                std::unique_ptr<flutter::MethodResult<>> result);
  void StopPlayback(std::unique_ptr<flutter::MethodResult<>> result);

  static void CALLBACK WaveInProc(HWAVEIN hwi, UINT msg,
                                  DWORD_PTR instance, DWORD_PTR param1,
                                  DWORD_PTR param2);

  // Capture
  HWAVEIN wave_in_ = nullptr;
  std::vector<WAVEHDR> wave_headers_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> capture_sink_;
  std::atomic<bool> capturing_{false};
  static constexpr int kBufferCount = 4;
  static constexpr int kBufferSize = 3840;

  // Playback
  HWAVEOUT wave_out_ = nullptr;
  std::atomic<bool> playing_{false};
  std::mutex playback_mutex_;
};

#endif  // RUNNER_AUDIO_PLUGIN_H_
