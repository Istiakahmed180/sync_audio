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
- `SENTRY_AUTH_TOKEN`

`SENTRY_AUTH_TOKEN` is used by `sentry_dart_plugin` during the Flutter build
to upload Android, iOS/macOS, and Windows debug symbols to the configured
Sentry organization/project. Create the token with the minimum release-upload
scope required by Sentry and add it only as a GitHub Actions repository secret;
do not commit it to `pubspec.yaml` or `sentry.properties`.

The workflow decodes the keystore only inside the ephemeral runner and uploads
the resulting AAB as an artifact.

## Firebase App Distribution

The Firebase project is `syncmesh-audio` and the Android App ID is configured
in `tool/firebase_distribute.sh`. After building an APK, distribute it with:

```sh
./tool/firebase_distribute.sh build/app/outputs/flutter-apk/app-debug.apk
```

`build_app.sh` now uploads the generated release APK automatically after a
successful Android APK build. Set `UPLOAD_FIREBASE=false` when an upload is
not wanted:

```sh
UPLOAD_FIREBASE=false ./build_app.sh android
```

The upload is fail-fast: if Firebase CLI authentication or the upload fails,
the build script exits non-zero instead of reporting a false successful build.

Use `FIREBASE_ANDROID_APP_ID` to override the app ID in CI, and authenticate
the Firebase CLI with a service account or Firebase token in CI.

## Crash logging

Unhandled Flutter, platform, and zone errors are stored locally in a bounded,
redacted crash trail and forwarded to Firebase Crashlytics in Android, iOS,
and macOS release builds. Diagnostic JSON/text export includes the recent
local crash entries, with pairing codes and IPv4 addresses removed.
