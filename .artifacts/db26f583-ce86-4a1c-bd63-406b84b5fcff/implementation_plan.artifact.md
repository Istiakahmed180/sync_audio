# Implementation Plan - Fixing Audited Issues

This plan addresses the identified issues in the "Sync Audio" project, including memory leaks, socket conflicts, mDNS discovery limitations, and error handling robustness.

## User Review Required

> [!IMPORTANT]
> **UDP Socket Separation**: I will be splitting the shared `_socket` in `UdpAudioService` into `_hostSocket` and `_receiverSocket`. This allows a single device to act as both a Host and a Receiver (e.g., for testing) without resource conflicts.
>
> **mDNS Compression**: The manual mDNS responder will be updated to handle DNS name compression (pointers). This is a low-level change to ensure compatibility with all network devices.

## Proposed Changes

### Core Services

#### [MODIFY] [audio_codec.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/services/audio_codec.dart)
- Add `Future<void> dispose()` to `AudioEncoder` and `AudioDecoder` interfaces.
- Implement `dispose()` in `NativeOpusAudioEncoder` and `NativeOpusAudioDecoder` to explicitly release native Opus resources by calling `destroy()`.
- Ensure `Pcm16AudioEncoder` and other implementations have a no-op `dispose()`.

#### [MODIFY] [udp_audio_service.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/services/udp_audio_service.dart)
- **Memory Management**: Update `selectCodec` and `stopStreaming`/`stopReceiver` to properly dispose of the current encoder and decoder.
- **Socket Conflict**: Replace the single `_socket` with `_hostSocket` and `_receiverSocket`. Update all methods (`startStreaming`, `startReceiver`, etc.) to use the appropriate socket.
- **Error Handling**: Rate-limit or suppress repetitive decryption error messages in `_handleReceiverDatagram` to avoid flooding the UI.
- **Jitter Buffer**: Ensure a safe minimum margin is maintained even in Low Latency modes to prevent audio popping.

#### [MODIFY] [device_discovery_service.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/services/device_discovery_service.dart)
- **mDNS Compression**: Update `_readMdnsName` to correctly handle DNS name pointers (`0xC0` prefix). This ensures the discovery service can correctly parse compressed mDNS queries from various network stacks.

### Controllers (UI Logic)

#### [MODIFY] [host_controller.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/features/host/controllers/host_controller.dart)
- Ensure all timers and subscriptions are robustly cancelled in `onClose`.
- Add guard clauses to prevent overlapping discovery/connection tasks.

## Verification Plan

### Automated Tests
- I will run existing unit tests to ensure no regressions in packet encoding/decoding.
- I will add a test case for `mDNS` name parsing with compression if possible, or verify via manual simulation.

### Manual Verification
- **Memory Check**: Verify that switching between PCM and Opus multiple times doesn't cause a noticeable increase in memory usage.
- **Simultaneous Host/Receiver**: Start a Host stream and a Receiver on the same device to verify that they no longer conflict over the UDP socket.
- **Discovery**: Verify that the device is still discoverable on the network.
