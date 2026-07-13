# sync_audio

This project streams supported Android system audio as timestamped mono audio
over a local Wi-Fi network. PCM is the default codec and remains the fallback
for compatibility. Opus is available as an explicit host setting when both
devices run a build with the native Opus runtime initialized.

The transport has an explicit `AudioEncoder` / `AudioDecoder` boundary,
codec-tagged packets, AES-GCM packet protection, replay checks, and encrypted
TCP control after the pairing handshake. The app does not bypass Android
MediaProjection restrictions or DRM restrictions.

The current synchronization implementation estimates clock offset and drift
from UDP timing samples and schedules timestamped playback. It does not yet
perform sample-rate correction, a full adaptive jitter target, NSD discovery,
or an asymmetric authenticated key exchange. Per-device UDP encryption also
requires one shared pairing token; independent `IP=token` entries are still
supported for control pairing but do not enable encrypted audio fan-out.

See [docs/PHYSICAL_TESTING.md](docs/PHYSICAL_TESTING.md) for manual device
validation. Unit tests and an APK build do not establish physical-device
synchronization quality.

Run `flutter pub get`, then validate with `flutter analyze`, `flutter test`,
`flutter build apk --debug`, and `flutter build apk --release`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
