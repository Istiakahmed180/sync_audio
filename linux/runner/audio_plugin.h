#ifndef RUNNER_AUDIO_PLUGIN_H_
#define RUNNER_AUDIO_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <pulse/simple.h>
#include <pulse/error.h>
#include <thread>
#include <atomic>
#include <vector>
#include <mutex>

class AudioPlugin {
 public:
  explicit AudioPlugin(FlBinaryMessenger* messenger);
  ~AudioPlugin();

 private:
  void SetupCaptureChannel();
  void SetupPlaybackChannel();

  // Capture
  pa_simple* capture_handle_ = nullptr;
  std::thread capture_thread_;
  std::atomic<bool> capturing_{false};
  FlEventChannel* capture_stream_channel_ = nullptr;
  FlMethodChannel* capture_control_channel_ = nullptr;

  // Playback
  pa_simple* playback_handle_ = nullptr;
  std::atomic<bool> playing_{false};
  std::mutex playback_mutex_;
  FlMethodChannel* playback_channel_ = nullptr;

  FlBinaryMessenger* messenger_ = nullptr;

  // GLib-friendly callbacks
  static void CaptureControlCallback(FlMethodChannel* channel,
                                      FlMethodCall* method_call,
                                      gpointer user_data);
  static void PlaybackControlCallback(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data);
};

#endif  // RUNNER_AUDIO_PLUGIN_H_
