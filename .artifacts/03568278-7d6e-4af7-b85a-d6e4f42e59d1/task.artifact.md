# Sync Audio Feature Implementation Tasks

## Phase 1: Audio Visualization
- [x] Add `visualizerPcm` stream to `AudioStreamService` [MODIFY] `lib/services/udp_audio_service.dart`
- [x] Implement audio level calculation (RMS/Peak) in `UdpAudioService` (Exposed raw PCM for flexible visualization)
- [x] Create `AudioVisualizer` widget [NEW] `lib/shared/widgets/audio_visualizer.dart`
- [x] Add visualizer to Host screen [MODIFY] `lib/features/host/views/host_view.dart`
- [x] Add visualizer to Receiver screen [MODIFY] `lib/features/receiver/views/receiver_view.dart`

## Phase 2: Automatic Mic-based Calibration
- [x] Add `record` package for microphone access
- [x] Create `AudioCalibrationService` with chirp generation and peak detection [NEW] `lib/services/audio_calibration_service.dart`
- [x] Update `ControlCommandType` with calibration commands [MODIFY] `lib/models/control_command.dart`
- [x] Add `sendRawPcm` to `UdpAudioService` for chirp injection [MODIFY] `lib/services/udp_audio_service.dart`
- [x] Implement calibration trigger and result handling in `HostController` [MODIFY] `lib/features/host/controllers/host_controller.dart`
- [x] Implement calibration listener in `ReceiverController` [MODIFY] `lib/features/receiver/controllers/receiver_controller.dart`
- [x] Add "Auto-calibrate" button to Host UI [MODIFY] `lib/features/host/views/host_view.dart`

## Phase 3: Receiver-side Equalizer (EQ)
- [ ] Create `AudioEqualizer` service/logic
- [ ] Add EQ UI in Receiver settings
- [ ] Apply EQ filters to PCM stream in `UdpAudioService`

## Phase 4: Reliable Scheduled Streaming
- [ ] Integrate `android_alarm_manager_plus` or similar
- [ ] Implement background task for scheduled streaming
- [ ] Update `HostController` to use the new scheduler

## Phase 5: LAN Web Dashboard
- [ ] Add `shelf` or similar lightweight web server
- [ ] Create basic HTML/JS dashboard
- [ ] Expose API from `HostController`

## Phase 6: Audio Recording
- [ ] Add recording capability to `AudioPlaybackService`
- [ ] Add UI button and file management for recordings
