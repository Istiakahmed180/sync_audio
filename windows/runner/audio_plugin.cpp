#include "audio_plugin.h"
#include <flutter/event_stream_handler_functions.h>

AudioPlugin::AudioPlugin(flutter::BinaryMessenger* messenger) {
  SetupCaptureChannel(messenger);
  SetupPlaybackChannel(messenger);
}

AudioPlugin::~AudioPlugin() {
  if (capturing_) StopCapture(nullptr);
  if (playing_) StopPlayback(nullptr);
}

// ---- Capture ----

void AudioPlugin::SetupCaptureChannel(flutter::BinaryMessenger* messenger) {
  auto control_channel = std::make_unique<flutter::MethodChannel<>>(
      messenger, "sync_audio/win_audio_capture",
      &flutter::StandardMethodCodec::GetInstance());

  auto stream_channel = std::make_unique<flutter::EventChannel<>>(
      messenger, "sync_audio/win_audio_stream",
      &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<>> events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        capture_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        capture_sink_ = nullptr;
        return nullptr;
      });

  stream_channel->SetStreamHandler(std::move(handler));

  control_channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        const auto& method = call.method_name();
        if (method == "start") {
          StartCapture(call, std::move(result));
        } else if (method == "stop") {
          StopCapture(std::move(result));
        } else {
          result->NotImplemented();
        }
      });
}

void AudioPlugin::StartCapture(const flutter::MethodCall<>& call,
                                std::unique_ptr<flutter::MethodResult<>> result) {
  if (capturing_) {
    result->Error("ALREADY_STARTED", "Capture already running");
    return;
  }

  WAVEFORMATEX format = {};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 48000;
  format.wBitsPerSample = 16;
  format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  format.cbSize = 0;

  MMRESULT res = waveInOpen(&wave_in_, WAVE_MAPPER, &format,
                            reinterpret_cast<DWORD_PTR>(WaveInProc),
                            reinterpret_cast<DWORD_PTR>(this),
                            CALLBACK_FUNCTION);
  if (res != MMSYSERR_NOERROR) {
    result->Error("CAPTURE_OPEN", "Failed to open audio input");
    return;
  }

  wave_headers_.resize(kBufferCount);
  for (int i = 0; i < kBufferCount; i++) {
    wave_headers_[i].lpData = new char[kBufferSize];
    wave_headers_[i].dwBufferLength = kBufferSize;
    wave_headers_[i].dwFlags = 0;
    waveInPrepareHeader(wave_in_, &wave_headers_[i], sizeof(WAVEHDR));
    waveInAddBuffer(wave_in_, &wave_headers_[i], sizeof(WAVEHDR));
  }

  waveInStart(wave_in_);
  capturing_ = true;
  result->Success();
}

void AudioPlugin::StopCapture(
    std::unique_ptr<flutter::MethodResult<>> result) {
  if (!capturing_) {
    if (result) result->Success();
    return;
  }
  capturing_ = false;
  waveInStop(wave_in_);
  waveInReset(wave_in_);
  for (auto& hdr : wave_headers_) {
    waveInUnprepareHeader(wave_in_, &hdr, sizeof(WAVEHDR));
    delete[] hdr.lpData;
  }
  wave_headers_.clear();
  waveInClose(wave_in_);
  wave_in_ = nullptr;
  if (result) result->Success();
}

void CALLBACK AudioPlugin::WaveInProc(HWAVEIN hwi, UINT msg,
                                       DWORD_PTR instance, DWORD_PTR,
                                       DWORD_PTR) {
  auto* self = reinterpret_cast<AudioPlugin*>(instance);
  if (msg == WIM_DATA) {
    WAVEHDR* hdr = reinterpret_cast<WAVEHDR*>(instance);
    if (self->capturing_ && self->capture_sink_ && hdr->dwBytesRecorded > 0) {
      std::vector<uint8_t> buf(hdr->dwBytesRecorded);
      memcpy(buf.data(), hdr->lpData, hdr->dwBytesRecorded);
      flutter::EncodableValue value(buf);
      self->capture_sink_->Success(value);
    }
    if (self->capturing_ && self->wave_in_) {
      waveInAddBuffer(self->wave_in_, hdr, sizeof(WAVEHDR));
    }
  }
}

// ---- Playback ----

void AudioPlugin::SetupPlaybackChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<>>(
      messenger, "sync_audio/win_audio_playback",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        const auto& method = call.method_name();
        if (method == "initialize") {
          InitializePlayback(std::move(result));
        } else if (method == "writePcm") {
          WritePcm(call, std::move(result));
        } else if (method == "stop") {
          StopPlayback(std::move(result));
        } else {
          result->NotImplemented();
        }
      });
}

void AudioPlugin::InitializePlayback(
    std::unique_ptr<flutter::MethodResult<>> result) {
  if (playing_) {
    result->Error("ALREADY_PLAYING", "Playback already active");
    return;
  }

  WAVEFORMATEX format = {};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 48000;
  format.wBitsPerSample = 16;
  format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  format.cbSize = 0;

  MMRESULT res = waveOutOpen(&wave_out_, WAVE_MAPPER, &format, 0, 0,
                             CALLBACK_NULL);
  if (res != MMSYSERR_NOERROR) {
    result->Error("PLAYBACK_OPEN", "Failed to open audio output");
    return;
  }

  playing_ = true;
  result->Success();
}

void AudioPlugin::WritePcm(const flutter::MethodCall<>& call,
                            std::unique_ptr<flutter::MethodResult<>> result) {
  if (!playing_ || !wave_out_) {
    result->Error("NOT_INITIALIZED", "Playback not initialized");
    return;
  }

  const auto* args = std::get_if<std::vector<uint8_t>>(call.arguments());
  if (!args || args->empty()) {
    result->Success();
    return;
  }

  std::lock_guard<std::mutex> lock(playback_mutex_);

  WAVEHDR hdr = {};
  hdr.lpData = const_cast<char*>(reinterpret_cast<const char*>(args->data()));
  hdr.dwBufferLength = static_cast<DWORD>(args->size());
  hdr.dwFlags = 0;

  waveOutPrepareHeader(wave_out_, &hdr, sizeof(WAVEHDR));
  waveOutWrite(wave_out_, &hdr, sizeof(WAVEHDR));

  // Wait for buffer to finish playing
  while (!(hdr.dwFlags & WHDR_DONE) && playing_) {
    Sleep(1);
  }
  waveOutUnprepareHeader(wave_out_, &hdr, sizeof(WAVEHDR));

  result->Success();
}

void AudioPlugin::StopPlayback(
    std::unique_ptr<flutter::MethodResult<>> result) {
  if (!playing_) {
    if (result) result->Success();
    return;
  }
  playing_ = false;
  waveOutReset(wave_out_);
  waveOutClose(wave_out_);
  wave_out_ = nullptr;
  if (result) result->Success();
}
