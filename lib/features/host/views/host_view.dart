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

class HostView extends GetView<HostController> {
  const HostView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
            Text(
              'Connection setup',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                    .where((a) => controller.receiverPairingControllers.containsKey(a))
                    .map(
                      (address) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ReceiverTargetCard(
                          address: address,
                          pairingController:
                              controller.receiverPairingControllers[address]!,
                          onRemove: () => controller.removeReceiverIp(address),
                          session: controller.receiverSessionFor(address),
                          onConnect: () => controller.connectReceiver(address),
                          onDisconnect: () =>
                              controller.disconnectReceiver(address),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Each Receiver has its own connection control.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Test message is available after the Receiver connection is established.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Test message',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.testMessageController,
              enabled: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Message to send'),
            ),
            const SizedBox(height: 16),
            Obx(
              () => AppPrimaryButton(
                label: 'Send Test Message',
                icon: Icons.send_rounded,
                onPressed: controller.isConnected
                    ? controller.sendTestMessage
                    : null,
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
                onChanged: (value) {
                  if (value != null) controller.selectCodec(value);
                },
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => DropdownButtonFormField<LatencyMode>(
                initialValue: controller.latencyMode.value,
                decoration: const InputDecoration(labelText: 'Latency mode'),
                items: LatencyMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) controller.configureLatency(value);
                },
              ),
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
            TextField(
              controller: controller.receiverIpInputController,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => controller.addReceiverIp(),
              decoration: InputDecoration(
                labelText: 'Add receiver IP',
                hintText: '192.168.1.11',
                helperText: 'Receivers added in connection setup are reused here.',
                suffixIcon: IconButton(
                  tooltip: 'Add receiver',
                  onPressed: controller.addReceiverIp,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.discoverReceivers,
                icon: const Icon(Icons.wifi_find_rounded),
                label: const Text('Discover receivers on Wi-Fi'),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: controller.portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '5050',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.audioPortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Audio UDP port',
                hintText: '5051',
              ),
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
                children: controller.receiverSessions
                    .map(
                      (session) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ReceiverSessionCard(
                          session: session,
                          onAdjust: (delta) => controller
                              .adjustReceiverCalibration(session, delta),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Obx(
              () => controller.diagnostics.isEmpty
                  ? const SizedBox.shrink()
                  : Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Diagnostics · latency ${(controller.diagnostics['estimatedTotalLatencyMicros'] as int? ?? 0) ~/ 1000} ms · RTT ${(controller.diagnostics['roundTripTimeMicros'] as int? ?? 0) ~/ 1000} ms · buffer ${controller.diagnostics['currentJitterBufferPackets'] ?? 0} packets · loss ${(controller.diagnostics['packetLossPercent'] as num? ?? 0).toStringAsFixed(1)}%',
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Start System Audio',
                icon: Icons.graphic_eq_rounded,
                onPressed:
                    !controller.isConnected ||
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
                    controller.audioStatus.value == AudioStreamStatus.streaming
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
            const SizedBox(height: 20),
            Obx(
              () => _MessageCard(
                label: 'Last sent message',
                value: controller.lastSentMessage.value.isEmpty
                    ? 'None yet'
                    : controller.lastSentMessage.value,
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
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(value),
        ],
      ),
    ),
  );
}

class _ReceiverTargetCard extends StatelessWidget {
  const _ReceiverTargetCard({
    required this.address,
    required this.pairingController,
    required this.onRemove,
    required this.session,
    required this.onConnect,
    required this.onDisconnect,
  });

  final String address;
  final TextEditingController pairingController;
  final VoidCallback onRemove;
  final ReceiverSession? session;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                      Text(
                        address,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
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
  const _ReceiverSessionCard({required this.session, required this.onAdjust});

  final ReceiverSession session;
  final ValueChanged<int> onAdjust;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.speaker_group_outlined),
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
                      tooltip: 'Make receiver earlier',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onAdjust(-5),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Make receiver later',
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
