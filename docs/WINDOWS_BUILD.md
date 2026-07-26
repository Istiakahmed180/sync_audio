# Windows build from macOS

The repository builds the Windows desktop app and Inno Setup installer in
GitHub Actions. A local Windows machine is not required.

## How to run

1. Push the repository to GitHub.
2. Open **Actions → Build Windows installer**.
3. Select **Run workflow**, or push to `main`/`master`.
4. When the job finishes, download one of these artifacts:
   - `SyncMesh-Audio-Windows-installer` — `SyncAudioSetup.exe`
   - `SyncMesh-Audio-Windows-portable` — portable Flutter release folder

The workflow runs `flutter analyze`, `flutter test`, `flutter build windows
--release`, and then compiles `installer/SyncAudio.iss` with Inno Setup.
