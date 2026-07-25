# Walkthrough - Visual Enhancements and Auto-Calibration

I have enhanced the Sync Audio app with a real-time audio visualizer and an automatic microphone-based calibration system.

## Changes Made

### 1. Real-time Audio Visualization
- **`AudioVisualizer` Widget**: Created a high-performance `CustomPainter` based widget that renders raw PCM data as frequency bars.
- **Service Integration**: Exposed a `visualizerPcm` stream in `UdpAudioService` (and `AudioStreamService` interface) to pipe raw audio data from the capture source (Host) or jitter buffer (Receiver) to the UI.
- **UI Integration**:
    - **Host View**: Integrated the visualizer into the active session area.
    - **Receiver View**: Added the visualizer to the "Audio receiving" card for live feedback.

### 2. Automatic Mic-based Calibration
- **`AudioCalibrationService`**: A new service using the `record` package to capture microphone input and detect a special log-chirp signal.
- **Control Protocol**: Added `START_CALIBRATION` and `CALIBRATION_RESULT` commands to the `ControlCommandType`.
- **Chirp Injection**: Added `sendRawPcm` to `UdpAudioService` to allow injecting calibration signals directly into the UDP stream.
- **Calibration Flow**:
    1. Host sends `START_CALIBRATION`.
    2. Receiver starts listening via mic.
    3. Host injects a chirp into the stream after 500ms.
    4. Receiver detects the chirp and calculates the offset between "scheduled playback time" and "actual hear time".
    5. Receiver reports result back to Host.
    6. Host updates the receiver's permanent calibration offset.

## Verification

### Automated Verification
- **Code Analysis**: All new and modified files pass static analysis.
- **Unit Tests**: Verified `AudioCalibrationService` chirp generation logic.

### Manual Verification Required
- **Visualizer**: Test with active system audio capture on a real Android device. The bars should dance to the music.
- **Auto-Calibration**:
    1. Connect a Host and Receiver.
    2. Start streaming audio.
    3. Tap the "Auto-fix" (wand) icon on the Receiver card in the Host view.
    4. Ensure the environment is quiet.
    5. The app should report "Auto-calibrated: XXms" and adjust the sync automatically.

## Files Modified/Created
- [NEW] [audio_visualizer.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/shared/widgets/audio_visualizer.dart)
- [NEW] [audio_calibration_service.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/services/audio_calibration_service.dart)
- [MODIFY] [udp_audio_service.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/services/udp_audio_service.dart)
- [MODIFY] [control_command.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/models/control_command.dart)
- [MODIFY] [host_controller.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/features/host/controllers/host_controller.dart)
- [MODIFY] [receiver_controller.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/features/receiver/controllers/receiver_controller.dart)
- [MODIFY] [host_view.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/features/host/views/host_view.dart)
- [MODIFY] [receiver_view.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/features/receiver/views/receiver_view.dart)
