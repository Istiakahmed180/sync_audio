# Physical multi-device validation

Use one Android phone as the Host and one to three Android phones as
Receivers. This checklist is manual validation guidance, not an automated
test result. The UI's latency modes target different buffering trade-offs;
they do not guarantee a particular latency on every Android device.
All devices must be on the same Wi-Fi network, with client isolation disabled.

1. Build and install the debug APK on every device:

   ```sh
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

2. On each Receiver, open the app, note its pairing code, and start the Receiver.
3. On the Host, use “Discover receivers on Wi-Fi” or enter each receiver IP. For one shared code, enter `123456`; for independent receiver codes, enter comma-separated entries such as `192.168.1.10=123456,192.168.1.11=654321`.
4. Select Ultra Low, Balanced, and Stable modes separately. Use PCM first and measure baseline latency with a clap or short sharp transient. Record the UI diagnostics: estimated latency, RTT, buffer packets, target buffer, loss, underruns, drift estimate, and applied correction.
   With no pairing token and PCM selected, the app attempts the native Android
   sender/receiver path. With encryption or Opus selected, it uses the existing
   Dart transport fallback. Confirm the active path in native diagnostics and
   do not compare results from different paths as if they were identical.
5. Stop the stream, select Opus, and verify that the receiver reports the same codec before judging output. Compare latency, dropouts, and audio quality with PCM.
6. Connect TCP, grant MediaProjection permission, start supported system audio, and confirm every Receiver reports audio playback. Android may deny capture for protected or DRM-controlled content; that is expected.
7. Stop and restart one Receiver while streaming. Confirm its TCP status transitions through reconnecting and that it resumes after the server is available. Repeat after force-stopping and relaunching the app.
8. Lock the screen, background the app, and repeat on a battery-restricted device. Record whether the foreground capture service remains alive.
9. Test one, two, and three Receivers on the same router and on a phone hotspot. Confirm client isolation is disabled and record each device's IP, Android version, codec, RTT, offset, jitter, drift estimate, applied correction, target/current buffer, loss, underruns, and Receiver-to-Receiver timing difference.
10. Run a continuous 30–60 minute stream. Confirm there is no continuously increasing drift, no unbounded buffer growth, and no repeated underruns on stable Wi-Fi.
11. Walk the Host and Receivers to a busier Wi-Fi area. Record buffer status, dropped packets, and audible gaps; do not interpret this test as proof of zero latency or perfect synchronization.
12. Use the per-Receiver ±5 ms calibration controls for residual speaker/device latency differences and repeat the test with all devices playing the same transient sound. Reset calibration and repeat once more.

For encrypted transport, use one shared pairing token, restart the session, and confirm that audio stops when the token is changed or a packet is tampered with. Never paste pairing tokens into bug reports.

The current native path is PCM16-only. It supports the established AES-GCM
session format when one shared pairing token is used; Opus and per-IP token
fan-out remain on the established Dart fallback.

Expected engineering targets, to be measured rather than assumed:

- Good local Wi-Fi host-to-receiver latency: approximately 40–80 ms.
- Best-case latency: approximately 25–50 ms.
- Receiver-to-Receiver timing difference: approximately 10–30 ms.
- No continuously increasing drift over 30–60 minutes.

For diagnostics, capture `adb logcat` from each Android device while testing and
redact pairing tokens, IP addresses, and captured audio. Physical-device
validation must be performed manually; Flutter unit tests and an APK build do
not replace it. Opus, encryption quality, long-running drift, and multi-device
latency remain unvalidated until these steps are run on real devices.
