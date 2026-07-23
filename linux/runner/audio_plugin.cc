#include "audio_plugin.h"

#include <sys/utsname.h>
#include <unistd.h>

#include <string>

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
  SetupDeviceInfoChannel();
}

void AudioPlugin::SetupDeviceInfoChannel() {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(
      messenger_, "sync_audio/device_info", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel*, FlMethodCall* method_call, gpointer) {
        struct utsname system_info = {};
        uname(&system_info);
        char host_name[256] = {};
        gethostname(host_name, sizeof(host_name) - 1);
        const std::string device_name = host_name[0] == '\0'
            ? "Linux PC"
            : std::string(host_name);

        const gchar* method = fl_method_call_get_name(method_call);
        if (g_strcmp0(method, "getDeviceName") == 0) {
          g_autoptr(FlValue) name = fl_value_new_string(device_name.c_str());
          fl_method_call_respond_success(method_call, name, nullptr);
          return;
        }
        if (g_strcmp0(method, "getDeviceInfo") == 0) {
          g_autoptr(FlValue) info = fl_value_new_map();
          fl_value_set_string(info, "platform", fl_value_new_string("Linux"));
          fl_value_set_string(info, "manufacturer",
                              fl_value_new_string("Linux community"));
          fl_value_set_string(info, "model",
                              fl_value_new_string(system_info.machine));
          fl_value_set_string(info, "deviceName",
                              fl_value_new_string(device_name.c_str()));
          fl_value_set_string(info, "osVersion",
                              fl_value_new_string(system_info.release));
          fl_value_set_string(info, "build",
                              fl_value_new_string(system_info.version));
          fl_method_call_respond_success(method_call, info, nullptr);
          return;
        }
        fl_method_call_respond_not_implemented(method_call);
      },
      this, nullptr);
  g_object_unref(channel);
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
