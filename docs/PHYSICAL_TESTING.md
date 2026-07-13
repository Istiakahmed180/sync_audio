# Physical multi-device validation

Use one Android phone as the Host and one to three Android phones as
Receivers. This checklist is manual validation guidance, not an automated
test result.
All devices must be on the same Wi-Fi network, with client isolation disabled.

1. Build and install the debug APK on every device:

   ```sh
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

2. On each Receiver, open the app, note its pairing code, and start the Receiver.
3. On the Host, use “Discover receivers on Wi-Fi” or enter each receiver IP. For one shared code, enter `123456`; for independent receiver codes, enter comma-separated entries such as `192.168.1.10=123456,192.168.1.11=654321`.
4. First select PCM and verify the one-Receiver path. Then stop the stream, select Opus on both sides, and verify that the receiver reports the same codec before judging audio output.
5. Connect TCP, grant MediaProjection permission, start supported system audio, and confirm every Receiver reports audio playback. Android may deny capture for protected or DRM-controlled content; that is expected.
6. Stop and restart one Receiver while streaming. Confirm its TCP status transitions through reconnecting and that it resumes after the server is available. Repeat after force-stopping and relaunching the app.
7. Lock the screen, background the app, and repeat on a battery-restricted device. Record whether the foreground capture service remains alive.
8. Test one, two, and three Receivers on the same router and on a phone hotspot. Confirm client isolation is disabled and record each device's IP, Android version, codec, RTT, offset, drift estimate, buffer packets, and dropped packets.
9. Walk the Host and Receivers to a busier Wi-Fi area. Record buffer status, dropped packets, and audible gaps; do not interpret this test as proof of zero latency or perfect synchronization.
10. Use the per-Receiver ±5 ms calibration controls for residual speaker/device latency differences and repeat the test with all devices playing the same transient sound.

For encrypted transport, use one shared pairing token, restart the session, and confirm that audio stops when the token is changed or a packet is tampered with. Never paste pairing tokens into bug reports.

For diagnostics, capture `adb logcat` from each Android device while testing and
redact pairing tokens, IP addresses, and captured audio. Physical-device
validation must be performed manually; Flutter unit tests and an APK build do
not replace it. Opus, encryption quality, long-running drift, and multi-device
latency remain unvalidated until these steps are run on real devices.
