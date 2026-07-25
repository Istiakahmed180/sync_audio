# Sync Audio Feature Expansion Plan

Based on the current project structure and mature implementation of the core audio synchronization engine, I have identified several high-value features that can be implemented to enhance the user experience and functionality.

## Proposed Features

### 1. Automatic Mic-based Calibration
Currently, users must manually adjust the "Playback Offset" to compensate for Bluetooth latency or speaker processing delay.
- **Implementation:**
    - The Host sends a short, unique audio pulse (chirp).
    - The Receiver uses its microphone to listen for this pulse.
    - By comparing the pulse's arrival time with its expected time (based on the synchronized network clock), the app can calculate the **exact physical latency**.
    - This offset is then applied automatically to the `playbackCalibrationMicros`.

### 2. Real-time Audio Visualization
Adding visual feedback on both Host and Receiver screens.
- **Implementation:**
    - On the **Host**, visualize the captured system audio before it's sent.
    - On the **Receiver**, visualize the incoming audio stream after jitter-buffering.
    - Use a custom `CustomPainter` or a lightweight visualization library to display a waveform or frequency bars.

### 3. Receiver-side Equalizer (EQ)
Allow individual receivers to have different audio profiles (e.g., more bass for a subwoofer-connected device).
- **Implementation:**
    - Add a 5-band or 10-band EQ UI on the Receiver settings.
    - Apply digital filters to the PCM stream in the `AudioPlaybackService` before sending it to the hardware.

### 4. Reliable Scheduled Streaming (Android AlarmManager)
The current scheduler uses a 30-second polling timer, which might be unreliable if the app is optimized by the OS.
- **Implementation:**
    - Use Android's `AlarmManager` or `WorkManager` to ensure the audio stream starts/stops exactly at the scheduled time, even if the app is in a deep sleep state.

### 5. LAN Web Dashboard
A simple web page hosted by the Host device that allows anyone on the same Wi-Fi to see which receivers are connected and adjust their volumes.
- **Implementation:**
    - Start a lightweight HTTP server on the Host.
    - Serve a single-page app (HTML/JS) that communicates with the `HostController` via a local API.

### 6. Audio Recording
Capture and save the synchronized stream on the receiver.
- **Implementation:**
    - Add a "Record" button on the Receiver.
    - Pipe the buffered PCM stream into a `.wav` file encoder and save it to the device's downloads or music folder.

## Recommended First Steps

I recommend starting with **Automatic Mic-based Calibration** and **Audio Visualization** as they provide the most immediate "wow" factor and solve the biggest user pain point (Bluetooth sync).

## User Review Required

> [!IMPORTANT]
> **Automatic Calibration** will require `RECORD_AUDIO` permission on the **Receiver** side as well (currently it's mostly a Host requirement).

> [!TIP]
> **Audio Visualization** might slightly increase CPU usage. We should ensure it's efficient or can be disabled in settings.

## Open Questions

1. Which of these features would you like me to prioritize first?
2. For the **Equalizer**, do you prefer a simple "Bass/Treble" control or a full multi-band EQ?
3. Should the **Web Dashboard** be accessible without a password, or should it use the pairing code for security?
