# Build script variables

`scripts/build.sh` can build Android, macOS, or Windows by passing a target
argument. The default output directory is `dist`.

## Quick usage

```bash
bash scripts/build.sh android   # APK → dist/SyncMesh Audio.apk
bash scripts/build.sh windows   # Portable + Installer → dist/
bash scripts/build.sh mac       # App + DMG → dist/SyncMesh Audio.dmg
bash scripts/build.sh all       # All platforms
```

## Output locations

- Android: `dist/SyncMesh Audio.apk` or `dist/SyncMesh Audio.aab`
- macOS: `dist/SyncMesh Audio.dmg`
- Windows: `dist/SyncAudioSetup.exe` and `dist/windows-portable/`

## Android APK

```bash
bash scripts/build.sh android
```

Output: `dist/SyncMesh Audio.apk`

For an unsigned CI-friendly debug APK:

```bash
ANDROID_BUILD_MODE=debug bash scripts/build.sh android
```

Output: `dist/SyncMesh Audio-debug.apk`

## Android App Bundle

```bash
BUILD_TYPE=appbundle bash scripts/build.sh android
```

Output: `dist/SyncMesh Audio.aab`

## macOS DMG

```bash
bash scripts/build.sh mac
```

Output: `dist/SyncMesh Audio.dmg`

## Windows installer

Run on Windows, Git Bash, or a Windows CI runner with Inno Setup installed:

```bash
bash scripts/build.sh windows
```

Outputs:

- `dist/SyncAudioSetup.exe`
- `dist/windows-portable/`

To skip the installer and build only the portable release:

```bash
CREATE_WINDOWS_INSTALLER=false bash scripts/build.sh windows
```

Install Inno Setup if not present:

```bash
choco install innosetup
```

Set `BUILD_APP=false` to run preparation only without producing a build.

## CI builds

GitHub Actions uses `scripts/ci_build.sh` which wraps `scripts/build.sh`
with CI-specific settings:

```bash
./scripts/ci_build.sh android
./scripts/ci_build.sh macos
./scripts/ci_build.sh windows
```
