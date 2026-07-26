# Integration testing

The project has two permanent integration tests:

- `integration_test/app_test.dart` launches the real Flutter app and verifies
  the main Host/Receiver role-selection screen.
- `integration_test/network_flow_test.dart` uses the real TCP socket stack to
  exercise pairing on an Android/iOS/desktop test device.

Run the UI smoke test on a connected device with:

```bash
flutter test integration_test/app_test.dart -d <device-id>
```

Run the network flow test with:

```bash
flutter test integration_test/network_flow_test.dart -d <device-id>
```

For the Flutter Driver-compatible flow, use:

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d <device-id>
```

For physical multi-device audio testing, start a Receiver on one device,
connect a Host on another device to the Receiver's LAN IP, then record the
dashboard metrics while changing Wi-Fi conditions. The existing
`docs/PHYSICAL_TESTING.md` checklist covers the required measurements.
