import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/audio_stream_status.dart';
import '../../../models/connection_status.dart';
import '../../../models/receiver_session.dart';
import '../../../services/audio_codec.dart';
import '../../../services/latency_metrics.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../../../shared/widgets/app_error_banner.dart';
import '../../../shared/widgets/connection_overview_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../controllers/host_controller.dart';
import 'qr_scanner_view.dart';

class HostView extends GetView<HostController> {
  const HostView({super.key});

  @override
  Widget build(BuildContext context) {
    return _HostDiscoveryLifecycle(
      controller: controller,
      child: Scaffold(
        appBar: AppBar(title: const Text('Host Device')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Connection status',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Obx(
                    () => StatusBadge(
                      label: controller.connectionStatus.value.label,
                    ),
                  ),
                ],
              ),
              Obx(
                () => controller.errorMessage.value == null
                    ? const SizedBox.shrink()
                    : AppErrorBanner(
                        message: controller.errorMessage.value!,
                        onDismiss: () => controller.errorMessage.value = null,
                      ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => ConnectionOverviewCard(
                  title: 'Host connection',
                  state: controller.connectionStatus.value.label,
                  icon: controller.isConnected
                      ? Icons.check_circle_outline
                      : Icons.wifi_tethering_rounded,
                  busy: controller.isConnecting,
                  message: switch (controller.connectionStatus.value) {
                    ConnectionStatus.connected =>
                      'Receiver connection established. You can send a test message or start system audio.',
                    ConnectionStatus.connecting =>
                      'Connecting to the Receiver. Keep both devices on the same Wi‑Fi network.',
                    ConnectionStatus.error =>
                      'Connection failed. Check the Receiver IP, port, and pairing code, then try again.',
                    _ =>
                      'Enter the Receiver IP, port, and required pairing code to begin.',
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Connection setup',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                    onPressed: () async {
                      final data = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const QrScannerView(),
                        ),
                      );
                      if (data != null && context.mounted) {
                        controller.addReceiverFromQrData(data);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Use the IP address and pairing code shown on the Receiver screen.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller.receiverIpInputController,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => controller.addReceiverIp(),
                decoration: InputDecoration(
                  labelText: 'Receiver IP address',
                  hintText: '192.168.1.10',
                  suffixIcon: IconButton(
                    tooltip: 'Add receiver',
                    onPressed: controller.addReceiverIp,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller.pairingTokenController,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Receiver pairing code (required)',
                  hintText: '12345678',
                  counterText: '',
                  helperText:
                      'This code will be assigned to the next Receiver you add.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller.portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '5050',
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => Column(
                  children: controller.configuredReceiverIps
                      .where(
                        (a) => controller.receiverPairingControllers
                            .containsKey(a),
                      )
                      .map(
                        (address) {
                          final deviceName =
                              controller.discoveredDeviceNames[address];
                          final latencyMs =
                              controller.discoveredDeviceLatencyMs[address];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ReceiverTargetCard(
                              address: address,
                              deviceName: deviceName,
                              latencyMs: latencyMs,
                              pairingController:
                                  controller.receiverPairingControllers[address]!,
                              onRemove: () =>
                                  controller.removeReceiverIp(address),
                              session: controller.receiverSessionFor(address),
                              onConnect: () =>
                                  controller.connectReceiver(address),
                              onDisconnect: () =>
                                  controller.disconnectReceiver(address),
                            ),
                          );
                        },
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Obx(
                  () => TextButton.icon(
                    onPressed: controller.toggleDiscoveryPolling,
                    icon: controller.isDiscoveringReceivers.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            controller.isDiscoveryPolling.value
                                ? Icons.stop_circle_outlined
                                : Icons.wifi_find_rounded,
                          ),
                    label: Text(
                      controller.isDiscoveringReceivers.value
                          ? 'Searching…'
                          : controller.isDiscoveryPolling.value
                          ? 'Stop search'
                          : 'Search',
                    ),
                  ),
                ),
              ),
              Obx(
                () => Text(
                  controller.discoveryStatus.value,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'System audio',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Obx(
                () => DropdownButtonFormField<AudioCodecPreference>(
                  initialValue: controller.codecPreference.value,
                  onChanged: controller.isRestartingAudioSettings
                      ? null
                      : (value) {
                          if (value != null) controller.selectCodec(value);
                        },
                  decoration: const InputDecoration(labelText: 'Audio codec'),
                  items: const [
                    DropdownMenuItem(
                      value: AudioCodecPreference.auto,
                      child: Text('Auto'),
                    ),
                    DropdownMenuItem(
                      value: AudioCodecPreference.pcm,
                      child: Text('PCM'),
                    ),
                    DropdownMenuItem(
                      value: AudioCodecPreference.opus,
                      child: Text('Opus'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Obx(
                () => DropdownButtonFormField<LatencyMode>(
                  initialValue: controller.latencyMode.value,
                  onChanged: controller.isRestartingAudioSettings
                      ? null
                      : (value) {
                          if (value != null) controller.configureLatency(value);
                        },
                  decoration: const InputDecoration(labelText: 'Latency mode'),
                  items: LatencyMode.values
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(mode.label),
                        ),
                      )
                      .toList(),
                ),
              ),
              Text(
                'Changing these settings briefly restarts audio on all Receivers.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Capture supported app playback through Android MediaProjection and send it over UDP.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Zero latency is not physically possible. Lower latency may increase dropouts on unstable networks.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Obx(
                () => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Audio status'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${controller.receiverCount.value} receivers'),
                        const SizedBox(width: 10),
                        StatusBadge(label: controller.audioStatus.value.label),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => Column(
                  children: controller.displayReceiverSessions
                      .map(
                        (session) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ReceiverSessionCard(
                            session: session,
                            volume: controller.volumeForReceiver(
                              session.ipAddress,
                            ),
                            muted: controller.isMuted(session.ipAddress),
                            onVolumeChanged: (v) => controller
                                .setReceiverVolume(session.ipAddress, v),
                            onMuteToggle: () =>
                                controller.toggleMute(session.ipAddress),
                            onAdjust: (delta) => controller
                                .adjustReceiverCalibration(session, delta),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => AppPrimaryButton(
                  label: 'Start System Audio',
                  icon: Icons.graphic_eq_rounded,
                  onPressed:
                      !controller.isConnected ||
                          controller.isStartingSystemAudio ||
                          controller.audioStatus.value ==
                              AudioStreamStatus.streaming
                      ? null
                      : controller.startSystemAudioStream,
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => AppPrimaryButton(
                  label: 'Stop System Audio',
                  icon: Icons.stop_circle_outlined,
                  onPressed:
                      controller.audioStatus.value ==
                          AudioStreamStatus.streaming
                      ? controller.stopSystemAudioStream
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Obx(
                () => Text(
                  controller.isConnected
                      ? controller.audioStatus.value ==
                                AudioStreamStatus.streaming
                            ? 'System audio is being sent to the connected Receivers.'
                            : 'Connect a Receiver, then start system audio when you are ready.'
                      : 'Connect a Receiver before starting system audio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              const _InfoMessage(
                text:
                    'Supported system audio is captured on Android and sent to each receiver with timestamped packets and clock-offset compensation.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostDiscoveryLifecycle extends StatefulWidget {
  const _HostDiscoveryLifecycle({
    required this.controller,
    required this.child,
  });

  final HostController controller;
  final Widget child;

  @override
  State<_HostDiscoveryLifecycle> createState() =>
      _HostDiscoveryLifecycleState();
}

class _HostDiscoveryLifecycleState extends State<_HostDiscoveryLifecycle> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    widget.controller.stopDiscoveryPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReceiverTargetCard extends StatelessWidget {
  const _ReceiverTargetCard({
    required this.address,
    required this.pairingController,
    required this.onRemove,
    required this.session,
    required this.onConnect,
    required this.onDisconnect,
    this.deviceName,
    this.latencyMs,
  });

  final String address;
  final String? deviceName;
  final int? latencyMs;
  final TextEditingController pairingController;
  final VoidCallback onRemove;
  final ReceiverSession? session;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  String get _displayName => (deviceName != null && deviceName!.isNotEmpty) ? deviceName! : address;

  Widget _signalIndicator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isConnected = session?.controlStatus == ControlConnectionStatus.connected;
    if (isConnected) {
      return Icon(Icons.link_rounded, size: 14, color: scheme.primary);
    }
    if (latencyMs == null) {
      return Icon(Icons.wifi_rounded, size: 14, color: scheme.outline);
    }
    final ms = latencyMs!;
    if (ms <= 20) {
      return Icon(Icons.wifi_rounded, size: 14, color: Colors.green);
    } else if (ms <= 50) {
      return Icon(Icons.wifi_rounded, size: 14, color: Colors.orange);
    } else {
      return Icon(Icons.wifi_find_rounded, size: 14, color: Colors.red);
    }
  }

  String _signalLabel() {
    if (session?.controlStatus == ControlConnectionStatus.connected) return 'Connected';
    if (latencyMs == null) return 'Unknown';
    final ms = latencyMs!;
    if (ms <= 20) return 'Excellent';
    if (ms <= 50) return 'Good';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.speaker_group_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _displayName,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _signalIndicator(context),
                          const SizedBox(width: 4),
                          Text(
                            _signalLabel(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                      if (deviceName != null && deviceName!.isNotEmpty)
                        Text(
                          address,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      TextField(
                        controller: pairingController,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        decoration: const InputDecoration(
                          labelText: 'Pairing code',
                          hintText: '12345678',
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove receiver',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusBadge(
                  label: session?.controlStatus.label ?? 'TCP offline',
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      session?.controlStatus ==
                              ControlConnectionStatus.connecting ||
                          session?.controlStatus ==
                              ControlConnectionStatus.reconnecting
                      ? null
                      : session?.controlStatus ==
                            ControlConnectionStatus.connected
                      ? onDisconnect
                      : onConnect,
                  icon: Icon(
                    session?.controlStatus == ControlConnectionStatus.connected
                        ? Icons.link_off_rounded
                        : Icons.link_rounded,
                  ),
                  label: Text(
                    session?.controlStatus == ControlConnectionStatus.connected
                        ? 'Disconnect'
                        : session?.controlStatus ==
                                  ControlConnectionStatus.connecting ||
                              session?.controlStatus ==
                                  ControlConnectionStatus.reconnecting
                        ? 'Connecting…'
                        : 'Connect',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiverSessionCard extends StatelessWidget {
  const _ReceiverSessionCard({
    required this.session,
    required this.volume,
    required this.muted,
    required this.onVolumeChanged,
    required this.onMuteToggle,
    required this.onAdjust,
  });

  final ReceiverSession session;
  final double volume;
  final bool muted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggle;
  final ValueChanged<int> onAdjust;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              muted ? Icons.volume_off_rounded : Icons.speaker_group_outlined,
              color: muted ? Colors.grey : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.ipAddress,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${session.controlStatus.label} · RTT ${session.roundTripTimeMicros ~/ 1000} ms · offset ${session.clockOffsetMicros ~/ 1000} ms · drift ${session.clockDriftPpm} ppm',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: muted ? 'Unmute' : 'Mute',
                        visualDensity: VisualDensity.compact,
                        onPressed: onMuteToggle,
                        icon: Icon(
                          muted ? Icons.volume_off : Icons.volume_up,
                          size: 18,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: muted ? 0 : volume,
                          min: 0,
                          max: 1.5,
                          onChanged: (v) {
                            if (v > 0) onVolumeChanged(v);
                          },
                        ),
                      ),
                      Text(
                        '${(muted ? 0 : volume * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(label: session.status.label),
                Text('cal ${session.playbackCalibrationMicros ~/ 1000} ms'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Earlier',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onAdjust(-5),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Later',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onAdjust(5),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
