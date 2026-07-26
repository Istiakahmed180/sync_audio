# Build script variables

`build_app.sh` can build Android, macOS, or Windows by changing variables. The
default output directory is `dist`.

## One-command multi-platform build

Edit the platform toggles at the top of `build_app.sh`:

```bash
BUILD_ANDROID=true
BUILD_MACOS=true
BUILD_WINDOWS=false
OUTPUT_DIR=dist
```

Then run only:

```bash
./build_app.sh
```

The script builds every platform set to `true`. On macOS, Windows desktop
cannot be built locally; use the GitHub Actions Windows runner for that target.

Output locations:

- Android: `dist/SyncMesh Audio.apk` or `dist/SyncMesh Audio.aab`
- macOS: `dist/SyncMesh Audio.dmg`
- Windows: `dist/SyncAudioSetup.exe` and `dist/windows-portable/`

## Android APK

```bash
BUILD_TARGET=android BUILD_TYPE=apk OUTPUT_DIR=dist ./build_app.sh
```

Output: `dist/SyncMesh Audio.apk`

For an unsigned CI-friendly debug APK:

```bash
BUILD_TARGET=android ANDROID_BUILD_MODE=debug OUTPUT_DIR=dist ./build_app.sh
```

Output: `dist/SyncMesh Audio-debug.apk`

## Android App Bundle

```bash
BUILD_TARGET=android BUILD_TYPE=appbundle OUTPUT_DIR=dist ./build_app.sh
```

Output: `dist/SyncMesh Audio.aab`

## macOS DMG

```bash
BUILD_TARGET=macos CREATE_MACOS_DMG=true OUTPUT_DIR=dist ./build_app.sh
```

Output: `dist/SyncMesh Audio.dmg`

## Windows installer

Run on Windows, Git Bash, or a Windows CI runner with Inno Setup installed:

```bash
BUILD_TARGET=windows CREATE_WINDOWS_INSTALLER=true OUTPUT_DIR=dist ./build_app.sh
```

Outputs:

- `dist/SyncAudioSetup.exe`
- `dist/windows-portable/`

To skip the installer and build only the portable release:

```bash
BUILD_TARGET=windows CREATE_WINDOWS_INSTALLER=false OUTPUT_DIR=dist ./build_app.sh
```

Set `BUILD_APP=false` to run preparation only without producing a build.
