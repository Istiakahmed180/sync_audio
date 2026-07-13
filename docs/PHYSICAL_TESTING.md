# Physical multi-device validation

Use one Android phone as the Host and at least two Android phones as Receivers.
All devices must be on the same Wi-Fi network, with client isolation disabled.

1. Build and install the debug APK on every device:

   ```sh
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

2. On each Receiver, open the app, note its pairing code, and start the Receiver.
3. On the Host, use “Discover receivers on Wi-Fi” or enter each receiver IP. For one shared code, enter `123456`; for independent receiver codes, enter comma-separated entries such as `192.168.1.10=123456,192.168.1.11=654321`.
4. Connect TCP, grant MediaProjection permission, start supported system audio, and confirm every Receiver reports audio playback.
5. Stop and restart one Receiver while streaming. Confirm its TCP status transitions through reconnecting and that it resumes after the server is available.
6. Walk the Host and Receivers to a busier Wi-Fi area. Record buffer status, dropped packets, and audible gaps; do not interpret this test as proof of zero latency or perfect synchronization.
7. Use the per-Receiver ±5 ms calibration controls for residual speaker/device latency differences and repeat the test with all devices playing the same transient sound.

For diagnostics, capture `adb logcat` from each Android device while testing. Physical-device validation must be performed manually; Flutter unit tests and an APK build do not replace it.
