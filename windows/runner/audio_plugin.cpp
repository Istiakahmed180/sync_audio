#include "audio_plugin.h"
#include <flutter/event_stream_handler_functions.h>
#include <algorithm>
#include <cstdint>
#include <cwctype>
#include <shellapi.h>

static flutter::EncodableList ListWaveOutDevices(UINT selected_device) {
  flutter::EncodableList devices;
  const UINT count = waveOutGetNumDevs();
  for (UINT index = 0; index < count; ++index) {
    WAVEOUTCAPSW caps = {};
    if (waveOutGetDevCapsW(index, &caps, sizeof(caps)) != MMSYSERR_NOERROR) {
      continue;
    }
    const std::wstring name(caps.szPname);
    const auto lower = [&name]() {
      std::wstring value = name;
      std::transform(value.begin(), value.end(), value.begin(), towlower);
      return value;
    }();
    const bool bluetooth = lower.find(L"bluetooth") != std::wstring::npos ||
        lower.find(L"bt ") != std::wstring::npos ||
        lower.find(L"headphone") != std::wstring::npos;
    flutter::EncodableMap device;
    device[flutter::EncodableValue("id")] =
        flutter::EncodableValue("waveout:" + std::to_string(index));
    device[flutter::EncodableValue("name")] =
        flutter::EncodableValue(std::string(name.begin(), name.end()));
    device[flutter::EncodableValue("kind")] =
        flutter::EncodableValue(bluetooth ? "bluetooth" : "system");
    device[flutter::EncodableValue("isBluetooth")] =
        flutter::EncodableValue(bluetooth);
    device[flutter::EncodableValue("isSelected")] =
        flutter::EncodableValue(selected_device == index);
    devices.push_back(flutter::EncodableValue(device));
  }
  return devices;
}

AudioPlugin::AudioPlugin(flutter::BinaryMessenger* messenger) {
  SetupCaptureChannel(messenger);
  SetupPlaybackChannel(messenger);
}

AudioPlugin::~AudioPlugin() {
  if (capturing_) StopCapture(nullptr);
  if (playing_) StopPlayback(nullptr);
}

// ---- Capture (WASAPI system-output loopback) ----

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
  std::string error;
  if (!StartWasapiLoopback(&error)) {
    result->Error("CAPTURE_OPEN", error.empty() ? "Failed to open system audio" : error);
    return;
  }
  result->Success();
}

void AudioPlugin::StopCapture(
    std::unique_ptr<flutter::MethodResult<>> result) {
  if (!capturing_) {
    if (result) result->Success();
    return;
  }
  capturing_ = false;
  if (capture_event_) SetEvent(capture_event_);
  if (capture_thread_.joinable()) capture_thread_.join();
  ReleaseWasapiLoopback();
  if (result) result->Success();
}

bool AudioPlugin::StartWasapiLoopback(std::string* error) {
  IMMDeviceEnumerator* enumerator = nullptr;
  HRESULT hr = CoCreateInstance(
      __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
      __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr)) {
    if (error) *error = "Could not access the Windows audio device list";
    return false;
  }

  hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &capture_device_);
  enumerator->Release();
  if (FAILED(hr)) {
    if (error) *error = "No default Windows playback device is available";
    return false;
  }

  hr = capture_device_->Activate(__uuidof(IAudioClient), CLSCTX_ALL,
                                 nullptr, reinterpret_cast<void**>(&capture_client_));
  if (FAILED(hr)) {
    if (error) *error = "Could not activate the Windows audio client";
    ReleaseWasapiLoopback();
    return false;
  }

  hr = capture_client_->GetMixFormat(&capture_format_);
  if (FAILED(hr)) {
    if (error) *error = "Could not read the Windows audio format";
    ReleaseWasapiLoopback();
    return false;
  }

  constexpr REFERENCE_TIME kBufferDuration = 20 * 10'000;
  hr = capture_client_->Initialize(
      AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
      kBufferDuration, 0, capture_format_, nullptr);
  if (FAILED(hr)) {
    if (error) *error = "Could not initialize Windows system-audio loopback";
    ReleaseWasapiLoopback();
    return false;
  }

  hr = capture_client_->GetService(__uuidof(IAudioCaptureClient),
                                   reinterpret_cast<void**>(&capture_reader_));
  if (FAILED(hr)) {
    if (error) *error = "Could not access the Windows audio capture buffer";
    ReleaseWasapiLoopback();
    return false;
  }

  capture_event_ = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  if (!capture_event_ || FAILED(capture_client_->SetEventHandle(capture_event_))) {
    if (error) *error = "Could not create the Windows audio capture event";
    ReleaseWasapiLoopback();
    return false;
  }

  capturing_ = true;
  hr = capture_client_->Start();
  if (FAILED(hr)) {
    capturing_ = false;
    if (error) *error = "Could not start Windows system-audio loopback";
    ReleaseWasapiLoopback();
    return false;
  }
  capture_thread_ = std::thread(&AudioPlugin::CaptureLoop, this);
  return true;
}

void AudioPlugin::CaptureLoop() {
  while (capturing_) {
    if (WaitForSingleObject(capture_event_, 100) != WAIT_OBJECT_0) continue;
    UINT32 packet_frames = 0;
    while (capturing_ && capture_reader_ &&
           SUCCEEDED(capture_reader_->GetNextPacketSize(&packet_frames)) &&
           packet_frames > 0) {
      BYTE* data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      if (FAILED(capture_reader_->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;

      const int channels = std::max<int>(capture_format_->nChannels, 1);
      const int bytes_per_sample = std::max<int>(capture_format_->wBitsPerSample / 8, 2);
      bool is_float = capture_format_->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
      if (capture_format_->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        const auto* extensible = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(capture_format_);
        is_float = IsEqualGUID(extensible->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
      }
      std::vector<uint8_t> pcm(static_cast<size_t>(frames) * 2, 0);
      if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data) {
        for (UINT32 frame = 0; frame < frames; ++frame) {
          double mixed = 0.0;
          for (int channel = 0; channel < channels; ++channel) {
            const size_t offset = (static_cast<size_t>(frame) * channels + channel) * bytes_per_sample;
            if (is_float) {
              mixed += static_cast<double>(*reinterpret_cast<float*>(data + offset));
            } else {
              mixed += static_cast<double>(*reinterpret_cast<int16_t*>(data + offset)) / 32768.0;
            }
          }
          const double normalized = std::max(-1.0, std::min(1.0, mixed / channels));
          const int16_t sample = static_cast<int16_t>(normalized * 32767.0);
          pcm[frame * 2] = static_cast<uint8_t>(sample & 0xff);
          pcm[frame * 2 + 1] = static_cast<uint8_t>((sample >> 8) & 0xff);
        }
      }
      if (capture_sink_ && !pcm.empty()) capture_sink_->Success(flutter::EncodableValue(pcm));
      capture_reader_->ReleaseBuffer(frames);
    }
  }
}

void AudioPlugin::ReleaseWasapiLoopback() {
  if (capture_client_) capture_client_->Stop();
  if (capture_event_) {
    CloseHandle(capture_event_);
    capture_event_ = nullptr;
  }
  if (capture_reader_) { capture_reader_->Release(); capture_reader_ = nullptr; }
  if (capture_client_) { capture_client_->Release(); capture_client_ = nullptr; }
  if (capture_device_) { capture_device_->Release(); capture_device_ = nullptr; }
  if (capture_format_) { CoTaskMemFree(capture_format_); capture_format_ = nullptr; }
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
        } else if (method == "listOutputs") {
          result->Success(ListWaveOutDevices(playback_device_id_));
        } else if (method == "selectOutput") {
          const auto* id = std::get_if<std::string>(call.arguments());
          if (!id || id->rfind("waveout:", 0) != 0 || playing_) {
            result->Error("OUTPUT_SELECT_FAILED", "Stop playback before selecting a Windows output");
          } else {
            try {
              playback_device_id_ = static_cast<UINT>(std::stoul(id->substr(8)));
              result->Success();
            } catch (...) {
              result->Error("INVALID_OUTPUT", "Audio output ID is invalid");
            }
          }
        } else if (method == "openOutputSettings") {
          const auto opened = reinterpret_cast<intptr_t>(ShellExecuteW(
              nullptr, L"open", L"ms-settings:sound", nullptr, nullptr,
              SW_SHOWNORMAL));
          if (opened <= 32) {
            result->Error("SETTINGS_OPEN_FAILED", "Could not open Windows Sound settings");
          } else {
            result->Success();
          }
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

  MMRESULT res = waveOutOpen(&wave_out_, playback_device_id_, &format, 0, 0,
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
