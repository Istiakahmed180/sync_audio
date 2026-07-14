import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/constants/app_constants.dart';
import '../../../models/audio_stream_status.dart';
import '../../../models/connection_status.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../../../shared/widgets/app_error_banner.dart';
import '../../../shared/widgets/connection_overview_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../controllers/receiver_controller.dart';

class ReceiverView extends GetView<ReceiverController> {
  const ReceiverView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receiver Device')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Server status',
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
                title: 'Receiver connection',
                state: controller.connectionStatus.value.label,
                icon: controller.isConnectedToHost.value
                    ? Icons.check_circle_outline
                    : Icons.speaker_group_rounded,
                busy:
                    controller.connectionStatus.value ==
                    ConnectionStatus.startingServer,
                message: !controller.isServerRunning.value
                    ? 'Start this Receiver first. The Host cannot connect while the server is stopped.'
                    : controller.isConnectedToHost.value
                    ? controller.audioStatus.value ==
                              AudioStreamStatus.receiving
                          ? 'Host connected and audio is being received.'
                          : 'Host connected. Audio will start when the Host starts streaming.'
                    : 'Waiting for a Host. Share the IP address and pairing code below.',
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextFormField(
                initialValue: controller.deviceName.value,
                onChanged: (value) => controller.deviceName.value = value,
                decoration: const InputDecoration(
                  labelText: 'Your device name',
                  hintText: 'Living Room Speaker',
                  helperText: 'This identifies your device to the Host.',
                  prefixIcon: Icon(Icons.speaker_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => _ConnectionInfoCard(
                deviceName: controller.deviceName.value,
                ipAddress: controller.localIpAddress.value,
                pairingCode: controller.pairingToken.value,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Message Host',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send your connection info or a custom message directly to the Host inside the app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.messageController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Your message',
                      hintText: 'Send a message to the Host…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: controller.isConnectedToHost.value
                      ? controller.sendMessageToHost
                      : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Obx(
              () => controller.lastSentMessage.value.isEmpty
                  ? const SizedBox.shrink()
                  : Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sent: ${controller.lastSentMessage.value}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.isConnectedToHost.value
                    ? controller.prepareConnectionInfo
                    : null,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Auto-fill my connection info'),
              ),
            ),
            const SizedBox(height: 16),
            Obx(
              () => AppPrimaryButton(
                label:
                    controller.connectionStatus.value ==
                        ConnectionStatus.startingServer
                    ? 'Starting…'
                    : 'Start Receiver',
                icon: Icons.play_arrow_rounded,
                isLoading:
                    controller.connectionStatus.value ==
                    ConnectionStatus.startingServer,
                onPressed: controller.isServerRunning.value
                    ? null
                    : controller.startServer,
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Stop Receiver',
                icon: Icons.stop_rounded,
                onPressed: controller.isServerRunning.value
                    ? controller.stopServer
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                controller.isServerRunning.value
                    ? 'This Receiver is discoverable and ready for a Host connection.'
                    : 'Start Receiver to open the control and audio listeners.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 28),
            Text('Buffer Health', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Obx(() => _BufferHealthCard(
              isReceiving: controller.isAudioReceiverRunning.value,
            )),
            const SizedBox(height: 28),
            Text(
              'PCM audio receiver',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Receive mono PCM packets over UDP and play them through Android AudioTrack.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const _DetailRow(
              label: 'Audio UDP port',
              value: '${AppConstants.audioPort}',
            ),
            const SizedBox(height: 12),
            Obx(
              () => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Audio status'),
                  StatusBadge(label: controller.audioStatus.value.label),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Start Audio Receiver',
                icon: Icons.volume_up_rounded,
                onPressed: controller.isAudioReceiverRunning.value
                    ? null
                    : controller.startAudioReceiver,
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Stop Audio Receiver',
                icon: Icons.volume_off_rounded,
                onPressed: controller.isAudioReceiverRunning.value
                    ? controller.stopAudioReceiver
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            Obx(
              () => _MessageCard(
                label: 'Connected host',
                value: controller.isConnectedToHost.value
                    ? 'Host connected'
                    : 'No host connected',
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => _MessageCard(
                label: 'Last sync ping',
                value: controller.lastSyncPing.value.isEmpty
                    ? 'None yet'
                    : controller.lastSyncPing.value,
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => _MessageCard(
                label: 'Last received message',
                value: controller.lastReceivedMessage.value.isEmpty
                    ? 'None yet'
                    : controller.lastReceivedMessage.value,
              ),
            ),
            const SizedBox(height: 12),
            const _InfoMessage(
              text:
                  'Start Receiver also starts the timestamped UDP audio receiver. The host synchronizes this device before playback begins.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionInfoCard extends StatelessWidget {
  const _ConnectionInfoCard({
    required this.deviceName,
    required this.ipAddress,
    required this.pairingCode,
  });

  final String deviceName;
  final String ipAddress;
  final String pairingCode;

  String get _connectionInfo => '$ipAddress:5050:$pairingCode';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = ipAddress.isNotEmpty && ipAddress != 'Not available' &&
        pairingCode.isNotEmpty && pairingCode != 'Loading…';

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Share with Host',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (hasData) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: _connectionInfo,
                    version: QrVersions.auto,
                    size: 200,
                    gapless: false,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Scan this QR code from the Host device',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
            _CopyableRow(
              label: 'IP Address',
              value: ipAddress,
              icon: Icons.wifi_rounded,
            ),
            const SizedBox(height: 12),
            _CopyableRow(
              label: 'Pairing Code',
              value: pairingCode,
              icon: Icons.vpn_key_rounded,
              valueStyle: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Give this code to the Host. It is required before a connection can be accepted.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasData
                    ? () {
                        final shareText =
                            'I\'m "$deviceName" — connect to:\nIP: $ipAddress:5050\nPairing code: $pairingCode\n\nScan or enter these on the Host device.';
                        Share.share(shareText, subject: 'Sync Audio — $deviceName');
                      }
                    : null,
                icon: const Icon(Icons.share_rounded),
                label: Text(hasData ? 'Share via app' : 'Start server to share'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  const _CopyableRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueStyle,
  });

  final String label;
  final String value;
  final IconData icon;
  final TextStyle? valueStyle;

  bool get _isValid => value.isNotEmpty &&
      value != 'Not available' && value != 'Loading…';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(value, style: valueStyle ?? theme.textTheme.bodyLarge),
            ],
          ),
        ),
        IconButton(
          tooltip: _isValid ? 'Copy $label' : 'Not available yet',
          icon: const Icon(Icons.copy_rounded, size: 20),
          onPressed: _isValid
              ? () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copied'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              : null,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(title: Text(label), subtitle: Text(value)),
  );
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

class _BufferHealthCard extends StatelessWidget {
  const _BufferHealthCard({required this.isReceiving});
  final bool isReceiving;

  @override
  Widget build(BuildContext context) {
    final status = isReceiving ? 'Active' : 'Idle';
    final color = isReceiving ? Colors.green : Colors.grey;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Status', style: TextStyle(fontWeight: FontWeight.w500)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                  child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isReceiving) ...[
              LinearProgressIndicator(
                value: _bufferHealth(isReceiving),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                color: _bufferColor(isReceiving),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                _bufferLabel(isReceiving),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Text('Start audio to monitor buffer', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  double _bufferHealth(bool r) => r ? 0.65 : 0;
  Color _bufferColor(bool r) => r ? Colors.orange : Colors.grey;
  String _bufferLabel(bool r) => r ? 'Buffer: Normal' : 'No data';
}
