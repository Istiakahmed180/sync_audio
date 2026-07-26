# Build script variables

`build_app.sh` can build Android, macOS, or Windows by changing variables. The
default output directory is `dist`.

## Android APK

```bash
BUILD_TARGET=android BUILD_TYPE=apk OUTPUT_DIR=dist ./build_app.sh
```

Output: `dist/SyncMesh Audio.apk`

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
