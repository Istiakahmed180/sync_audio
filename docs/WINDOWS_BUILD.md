# Multi-platform build from macOS

The repository builds Android, macOS, and Windows artifacts in parallel in
GitHub Actions. A local Windows machine is not required.

## How to run

1. Push the repository to GitHub.
2. Open **Actions → Build all platforms**.
3. Select **Run workflow**, or push to `main`/`master`.
4. When the jobs finish, download the artifacts:
   - `SyncMesh-Audio-Android-apk` — release APK when Android signing secrets are configured; otherwise a debug APK
   - `SyncMesh-Audio-macOS-dmg` — macOS DMG
   - `SyncMesh-Audio-Windows-installer` — `SyncAudioSetup.exe`
   - `SyncMesh-Audio-Windows-portable` — portable Flutter release folder

The workflow runs `flutter analyze` and `flutter test` once, then builds all
three platform artifacts. Windows is compiled on a Windows runner, macOS on a
macOS runner, and Android on an Ubuntu runner.

## Android release signing

To make GitHub build a signed release APK, add these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

Without these secrets, the Android job automatically produces a debug APK so
the multi-platform build still completes.
