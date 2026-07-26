# Release and CI setup

## Local Android release

Copy `android/key.properties.example` to `android/key.properties`, set the
real keystore values, and place the keystore at the configured path. The
credentials file and keystore are ignored by Git.

```sh
flutter build appbundle --release
```

The Gradle configuration refuses release tasks when any signing value is
missing. Debug builds remain available without release credentials.

## GitHub Actions

`.github/workflows/android.yml` runs `flutter analyze`, unit/widget tests, and
a debug APK build for pushes and pull requests. A published GitHub Release
also builds a signed AAB.

Configure these repository secrets before publishing a release:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

The workflow decodes the keystore only inside the ephemeral runner and uploads
the resulting AAB as an artifact.

## Crash logging

Unhandled Flutter, platform, and zone errors are stored locally in a bounded,
redacted crash trail. Diagnostic JSON/text export includes the recent crash
entries, with pairing codes and IPv4 addresses removed. This is intentionally
backend-neutral; a remote crash provider can be connected later without
changing the app error hooks.
