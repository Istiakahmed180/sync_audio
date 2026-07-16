# Sync Audio

Turn multiple devices into a synchronized speaker system. Stream audio from one
Android device and play it in sync across your other devices over a local Wi‑Fi
network.

---

## How it works

Sync Audio uses a **Host‑and‑Receiver** model over your local network.

- **Host** (Android only) — captures system audio from any app and sends it to
  all connected Receivers as timestamped packets.
- **Receiver** (any platform) — receives the Host's audio and plays it through
  its built-in speaker in sync with other Receivers.

One Host can stream to one or many Receivers simultaneously.

---

## Quick start

1. Connect all devices to the **same Wi‑Fi network**.
2. On your Android phone, open the app and select **Host Device**.
3. On every other device, open the app and select **Receiver Device**.
4. The Receiver shows a **pairing code** and a **QR code**.
5. On the Host, tap **Scan QR Code** and point the camera at the Receiver's
   screen — or enter the IP address and pairing code manually.
6. On the Host, enter the pairing code and press **Connect** next to the
   Receiver's card.
7. Once connected, press **Start System Audio** on the Host.
8. Audio starts playing on all Receivers in sync.

### Manual pairing (no camera)

If the Host device cannot scan QR codes, use the **Add manually** option on the
Host screen:

1. Read the IP address and pairing code from the Receiver's screen.
2. Enter the IP, pairing code, and port (default `5050`) on the Host.
3. Press the add button.

---

## Features

| Feature | Description |
|---------|-------------|
| **QR pairing** | Host scans the Receiver's QR code for one‑tap setup |
| **Manual pairing** | Enter IP and pairing code by hand |
| **Device discovery** | Host broadcasts to find nearby Receivers on the LAN |
| **Saved groups** | Save receiver sets as named groups for quick re‑setup |
| **Paired devices** | Previously connected devices appear for quick re‑add |
| **Scheduled streaming** | Set a daily time window for automatic audio start/stop |
| **Volume control** | Per‑receiver volume and mute on the Host |
| **Audio codecs** | PCM16 (default), Opus (optional with native runtime) |
| **Latency tuning** | Ultra‑low, balanced, and stable presets |
| **AES‑GCM encryption** | Audio packets and control channel encrypted after pairing |
| **Jitter buffer** | Adaptive bounded jitter buffer with drift correction |
| **Light/Dark theme** | System, light, and dark mode support |

---

## Permissions

### Android Host

| Permission | Why |
|------------|-----|
| `RECORD_AUDIO` | Required for audio capture |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PROJECTION` | Keep audio streaming when the app is in the background |
| `POST_NOTIFICATIONS` | Show a persistent notification while capturing audio |
| `CAMERA` | Scan QR codes from Receivers |
| `INTERNET` / `WAKE_LOCK` | Network access and keep CPU awake |

The first time you press **Start System Audio**, Android shows a system dialog
asking for screen recording consent. You must accept this to enable audio
capture.

### iOS / macOS

- `NSMicrophoneUsageDescription` — used for audio capture
- `NSCameraUsageDescription` — QR code scanning (iOS)

---

## Codec support

| Codec | Platforms | Notes |
|-------|-----------|-------|
| **PCM16** | All | Default, no external deps |
| **Opus** | Requires native Opus runtime | Lower bitrate, better quality. Built from the `opus_codec` plugin |

The Host auto‑negotiates the codec. If Opus is unavailable, it falls back to
PCM automatically.

---

## Building

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug    # Android debug
flutter build apk --release   # Android release
```

---

## Known limitations

- **Host must be Android.** Other platforms cannot capture system audio from
  other apps.
- **No sample‑rate resampling.** All devices must accept 44.1 kHz mono PCM.
- **No NSD/mDNS discovery.** UDP broadcast discovery only — all devices must be
  on the same subnet.
- **Single shared pairing token for encryption.** Per‑device tokens only work
  for control pairing, not for encrypted audio fan‑out.
- **Scheduling is best‑effort.** Runs on a 30‑second polling timer. Does not use
  Android AlarmManager.
- **Zero latency is not achievable.** Lower latency modes increase dropout risk
  on unstable networks.
- **No DRM‑protected audio capture.** Android MediaProjection restrictions
  apply.
