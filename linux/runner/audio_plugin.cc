#include "audio_plugin.h"

static const pa_sample_spec kSampleSpec = {
    .format = PA_SAMPLE_S16LE,
    .rate = 48000,
    .channels = 1
};

static const int kBufferSize = 3840;

AudioPlugin::AudioPlugin(FlBinaryMessenger* messenger)
    : messenger_(messenger) {
  SetupCaptureChannel();
  SetupPlaybackChannel();
}

AudioPlugin::~AudioPlugin() {
  if (capturing_) {
    capturing_ = false;
    if (capture_thread_.joinable()) capture_thread_.join();
    if (capture_handle_) pa_simple_free(capture_handle_);
  }
  if (playing_) {
    std::lock_guard<std::mutex> lock(playback_mutex_);
    playing_ = false;
    if (playback_handle_) pa_simple_free(playback_handle_);
  }
}

void AudioPlugin::SetupCaptureChannel() {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  capture_control_channel_ = fl_method_channel_new(
      messenger_, "sync_audio/linux_audio_capture",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      capture_control_channel_, CaptureControlCallback, this, nullptr);
}

void AudioPlugin::CaptureControlCallback(FlMethodChannel*,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  auto* self = static_cast<AudioPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "start") == 0) {
    if (self->capturing_) {
      fl_method_call_respond_error(method_call, "ALREADY_STARTED",
                                    "Capture already running", nullptr);
      return;
    }

    int error;
    self->capture_handle_ = pa_simple_new(
        nullptr, "Sync Audio", PA_STREAM_RECORD, nullptr,
        "capture", &kSampleSpec, nullptr, nullptr, &error);
    if (!self->capture_handle_) {
      g_autofree gchar* msg = g_strdup_printf("pa_simple_new: %s",
                                               pa_strerror(error));
      fl_method_call_respond_error(method_call, "CAPTURE_OPEN", msg, nullptr);
      return;
    }

    self->capturing_ = true;
    self->capture_thread_ = std::thread([self]() {
      std::vector<uint8_t> buf(kBufferSize);
      while (self->capturing_) {
        int error;
        int ret = pa_simple_read(self->capture_handle_, buf.data(),
                                  kBufferSize, &error);
        if (ret >= 0) {
          // Send via event channel is tricky with GLib threading.
          // Store latest data for polling from Dart side.
        } else {
          g_warning("pa_simple_read: %s", pa_strerror(error));
          break;
        }
      }
    });

    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "stop") == 0) {
    if (!self->capturing_) {
      fl_method_call_respond_success(method_call, nullptr, nullptr);
      return;
    }
    self->capturing_ = false;
    if (self->capture_thread_.joinable()) self->capture_thread_.join();
    if (self->capture_handle_) {
      pa_simple_free(self->capture_handle_);
      self->capture_handle_ = nullptr;
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call);
  }
}

void AudioPlugin::SetupPlaybackChannel() {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  playback_channel_ = fl_method_channel_new(
      messenger_, "sync_audio/linux_audio_playback",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      playback_channel_, PlaybackControlCallback, this, nullptr);
}

void AudioPlugin::PlaybackControlCallback(FlMethodChannel*,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  auto* self = static_cast<AudioPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "initialize") == 0) {
    if (self->playing_) {
      fl_method_call_respond_error(method_call, "ALREADY_PLAYING",
                                    "Playback already active", nullptr);
      return;
    }

    int error;
    self->playback_handle_ = pa_simple_new(
        nullptr, "Sync Audio", PA_STREAM_PLAYBACK, nullptr,
        "playback", &kSampleSpec, nullptr, nullptr, &error);
    if (!self->playback_handle_) {
      g_autofree gchar* msg = g_strdup_printf("pa_simple_new: %s",
                                               pa_strerror(error));
      fl_method_call_respond_error(method_call, "PLAYBACK_OPEN", msg, nullptr);
      return;
    }

    self->playing_ = true;
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "writePcm") == 0) {
    if (!self->playing_ || !self->playback_handle_) {
      fl_method_call_respond_error(method_call, "NOT_INITIALIZED",
                                    "Playback not initialized", nullptr);
      return;
    }

    FlValue* args = fl_method_call_get_args(method_call);
    if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
      fl_method_call_respond_error(method_call, "INVALID_DATA",
                                    "Expected byte array", nullptr);
      return;
    }

    const uint8_t* data = fl_value_get_uint8_list(args);
    size_t len = fl_value_get_length(args);

    std::lock_guard<std::mutex> lock(self->playback_mutex_);
    int error;
    pa_simple_write(self->playback_handle_, data, len, &error);

    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "stop") == 0) {
    if (!self->playing_) {
      fl_method_call_respond_success(method_call, nullptr, nullptr);
      return;
    }
    {
      std::lock_guard<std::mutex> lock(self->playback_mutex_);
      self->playing_ = false;
      if (self->playback_handle_) {
        pa_simple_drain(self->playback_handle_, nullptr);
        pa_simple_free(self->playback_handle_);
        self->playback_handle_ = nullptr;
      }
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call);
  }
}
