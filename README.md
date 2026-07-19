# Sync Audio

Turn multiple devices into a synchronized speaker system. Stream audio from an
Android device, macOS computer, or Windows computer and play it in sync across your other devices
over a local Wi‑Fi network.

---

## How it works

Sync Audio uses a **Host‑and‑Receiver** model over your local network.

- **Host** (Android, macOS, or Windows) — captures system audio and sends it to all
  connected Receivers as timestamped packets.
- **Receiver** (any platform) — receives the Host's audio and plays it through
  its built-in speaker in sync with other Receivers.

One Host can stream to one or many Receivers simultaneously.

On Windows, the Host uses native WASAPI loopback to capture the default
speaker output, so browser and system audio work without a virtual driver.

---

## Quick start

1. Connect all devices to the **same Wi‑Fi network**.
2. On the Android phone, Mac, or Windows computer that will provide the audio,
   open the app and select **Host Device**.
3. On every other device, open the app and select **Receiver Device**.
4. The Receiver shows a **pairing code** and a **QR code**.
5. On the Host, tap **Scan QR Code** and point the camera at the Receiver's
   screen — or enter the IP address and pairing code manually.
6. On the Host, enter the pairing code and press **Connect** next to the
   Receiver's card.
7. Once connected, press **Start System Audio** on the Host.
8. Audio starts playing on all Receivers in sync.

## macOS Host setup with BlackHole 2ch

BlackHole is the recommended macOS capture route for Sync Audio. It creates a
virtual audio device so browser audio can be captured without depending on the
Mac speaker volume or mute state. The project prefers a device whose name
contains `BlackHole` when it is installed.

### A. Install BlackHole 2ch

Using Homebrew:

```bash
brew install --cask blackhole-2ch
```

If Homebrew is not installed, download the signed installer from the
[BlackHole project](https://github.com/ExistentialAudio/BlackHole) and install
the 2-channel version. Restart audio applications after installation.

### B. Confirm the device

1. Open **System Settings → Sound**.
2. Select **Input**.
3. Confirm that **BlackHole 2ch** appears.
4. Select **BlackHole 2ch** and play a browser video.
5. Confirm that the **Input level** meters move.

If the meters do not move, the browser is not routed to BlackHole yet.

### C. Create a Multi-Output Device

Use this when you want to hear the audio locally on the Mac while also sending
it to Sync Audio:

1. Open **Applications → Utilities → Audio MIDI Setup**.
2. Click the `+` button at the bottom-left.
3. Choose **Create Multi-Output Device**.
4. Enable **Mac mini Speakers** (or the desired speakers).
5. Enable **BlackHole 2ch**.
6. Keep the built-in speakers as the primary/clock device when macOS offers
   that option.
7. In **System Settings → Sound → Output**, select this Multi-Output Device.

The audio route should then be:

```text
Browser / YouTube
        ↓
Multi-Output Device
   ↙             ↘
Mac speakers   BlackHole 2ch
                    ↓
             Sync Audio capture
                    ↓
              Wi‑Fi Receivers
```

### D. Grant macOS permissions

Open **System Settings → Privacy & Security** and allow Sync Audio in:

- **Screen & System Audio Recording** — required for the macOS fallback
  capture path.
- **Microphone** — required when the audio input engine is used.
- **Local Network**, if macOS shows a request for it.

Quit and relaunch Sync Audio after changing permissions.

### E. Start a macOS Host stream

1. Run the macOS app:

   ```bash
   flutter run -d macos
   ```

2. Open **Host Device** on the Mac.
3. Open **Receiver Device** on every Android/device Receiver and start its
   Receiver server.
4. Add each Receiver by scanning its QR code or entering its IP address and
   pairing code.
5. Confirm every Receiver shows **Connected**.
6. Select **Ultra Low** latency for a stable 5 GHz network.
7. Play a YouTube/browser video on the Mac and start system-audio streaming.

### F. Receiver and Wi‑Fi checklist

- Put the Mac and every Receiver on the same dedicated 5 GHz Wi‑Fi network.
- Disable VPN and router client/AP isolation.
- Avoid large downloads or video uploads on the same network.
- Keep the Receiver devices close to the access point during testing.
- Use each Receiver's calibration controls for residual speaker latency.
- If audio stutters, switch from **Ultra Low** to **Balanced**.

### G. Troubleshooting

**Connected, but no audio**

- Check that **BlackHole 2ch** input meters are moving.
- Confirm the Multi-Output Device includes both the Mac speakers and BlackHole.
- Restart the browser and Sync Audio after changing the output device.
- Confirm the Receiver is still showing **Start Receiver** as active.

**`Message too long` in the Mac terminal**

- Update to the latest project code and rebuild. macOS capture buffers are split
  into MTU-safe PCM packets by the app.

**High latency**

- Check Android Wi‑Fi link speed; 1–2 Mbps is too low for stable synchronized
  playback.
- Use 5 GHz, select Ultra Low, and keep the devices near the router.
- Calibrate each Receiver after the network is stable.

**No BlackHole input level**

- Select the Multi-Output Device as macOS Output.
- Verify that BlackHole 2ch is enabled inside that Multi-Output Device.
- Reopen Sound settings and restart the browser.

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

### Windows Host

Windows uses the default playback device as the capture source through WASAPI
loopback. No BlackHole or other virtual audio driver is required.

1. Set the Windows default output to the speakers/headphones to capture.
2. For predictable results, set that device to **48,000 Hz** in Windows Sound
   settings.
3. Allow Sync Audio through Windows Defender Firewall for **Private networks**
   if Windows asks. All devices must be on the same Wi‑Fi/LAN.
4. Start the Receiver, pair it from the Windows Host, press **Start System
   Audio**, and then play a browser video.

Windows does not need microphone permission for this system-audio path.

### iOS / macOS

- `NSMicrophoneUsageDescription` — used for audio capture
- `NSCameraUsageDescription` — QR code scanning (iOS)
- macOS 13+ — Screen & System Audio Recording permission for the fallback
  system-audio capture path
- macOS — BlackHole 2ch is recommended for deterministic browser/system-audio
  capture

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
flutter build windows --release  # Windows (run on a Windows machine)
```

The Windows release output is under `build/windows/x64/runner/Release/`.
Distribute the complete folder, not only the `.exe`, because Flutter runtime
files and DLLs are required.

---

## Known limitations

- **macOS capture requires routing.** For the most reliable browser capture,
  route audio through BlackHole 2ch, preferably with a Multi-Output Device.
- **Windows capture uses the default output.** Changing the default Windows
  speaker while streaming may require restarting the Host stream.
- **No universal sample-rate guarantee.** The recommended route is 48 kHz mono
  PCM; hardware or virtual devices with other formats may need OS-level format
  configuration.
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
