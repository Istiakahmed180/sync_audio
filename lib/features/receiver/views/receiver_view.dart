import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/audio_stream_status.dart';
import '../../../models/connection_status.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../../../shared/widgets/connection_overview_card.dart';
import '../../../shared/widgets/network_diagnostics_card.dart';
import '../../../shared/widgets/audio_visualizer.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../controllers/receiver_controller.dart';

class ReceiverView extends GetView<ReceiverController> {
  const ReceiverView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receiver Device')),
      body: SafeArea(
        child: ResponsiveContent(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: [
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
                  message:
                      controller.networkMismatchWarning.value ??
                      (!controller.isServerRunning.value
                          ? 'Start this Receiver first. The Host cannot connect while the server is stopped.'
                          : controller.isConnectedToHost.value
                          ? controller.audioStatus.value ==
                                    AudioStreamStatus.receiving
                                ? 'Host connected and audio is being received.'
                                : 'Host connected. Audio will start when the Host starts streaming.'
                          : 'Waiting for a Host. Share the IP address and pairing code below.'),
                ),
              ),
              Obx(
                () => controller.networkMismatchWarning.value == null
                    ? const SizedBox.shrink()
                    : Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: const Icon(Icons.sync_problem_rounded),
                          title: const Text('Network changed'),
                          subtitle: Text(
                            controller.networkMismatchWarning.value!,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Obx(() {
                if (controller.isIgnoringBatteryOptimizations.value) {
                  return const SizedBox.shrink();
                }
                return Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.battery_alert_rounded,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Battery optimization is active',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Background audio may stutter or disconnect. Disabling battery optimization is recommended for this app.',
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Obx(
                            () => TextButton(
                              onPressed:
                                  controller
                                      .isRequestingBatteryOptimization
                                      .value
                                  ? null
                                  : controller
                                        .requestIgnoreBatteryOptimizations,
                              child:
                                  controller
                                      .isRequestingBatteryOptimization
                                      .value
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Disable optimization'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Obx(
                () =>
                    controller.audioStatus.value == AudioStreamStatus.receiving
                    ? _AudioReceivingCard(
                        audioStatus: controller.audioStatus.value,
                        visualizerStream: controller.visualizerPcm,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Obx(
                () => NetworkDiagnosticsCard(
                  diagnostics: controller.diagnosticsData,
                  isActive: controller.isAudioReceiverRunning.value,
                ),
              ),
              Obx(
                () => DiagnosticReportButton(
                  scope: 'receiver',
                  diagnostics: controller.diagnosticsData,
                  networkInfo: controller.localNetworkInfo.value,
                  deviceInfo: controller.deviceInfoData,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextFormField(
                  controller: controller.deviceNameController,
                  onChanged: controller.setDeviceName,
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
              const SizedBox(height: 12),
              Obx(
                () => _ConnectionInfoCard(
                  deviceName: controller.deviceName.value,
                  ipAddress: controller.localIpAddress.value,
                  pairingCode: controller.pairingToken.value,
                  deviceId: controller.deviceId.value,
                  expiresAt: controller.pairingTokenExpiresAt.value,
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => _ReceiverNetworkCard(
                  networkInfo: controller.localNetworkInfo.value,
                  onRefresh: controller.refreshLocalNetworkInfo,
                ),
              ),
              const SizedBox(height: 12),
              Obx(
                () => _TrustedDevicesCard(
                  devices: controller.trustedDevices.toList(growable: false),
                  names: Map<String, String>.from(
                    controller.trustedDeviceNames,
                  ),
                  onRevoke: controller.revokeTrustedDevice,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiverNetworkCard extends StatelessWidget {
  const _ReceiverNetworkCard({
    required this.networkInfo,
    required this.onRefresh,
  });

  final String networkInfo;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connected network',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(networkInfo, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh network',
              onPressed: () => onRefresh(),
              icon: const Icon(Icons.refresh_rounded),
              visualDensity: VisualDensity.compact,
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
    required this.deviceId,
    required this.expiresAt,
  });

  final String deviceName;
  final String ipAddress;
  final String pairingCode;
  final String deviceId;
  final DateTime? expiresAt;

  String get _connectionInfo =>
      '$ipAddress:5050:$pairingCode:${Uri.encodeComponent(deviceName)}:$deviceId';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData =
        ipAddress.isNotEmpty &&
        ipAddress != 'Not available' &&
        pairingCode.isNotEmpty &&
        pairingCode != 'Loading…';

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
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
                'Show this QR code to the Host device to connect',
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
              'The Host needs this pairing code to connect.',
              style: theme.textTheme.bodySmall,
            ),
            if (expiresAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Code refreshes automatically every 10 minutes.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasData
                    ? () {
                        final shareText =
                            'I\'m "$deviceName" — connect to:\nIP: $ipAddress:5050\nPairing code: $pairingCode\n\nScan or enter these on the Host device.';
                        // ignore: deprecated_member_use
                        Share.share(
                          shareText,
                          subject: 'SyncMesh Audio — $deviceName',
                        );
                      }
                    : null,
                icon: const Icon(Icons.share_rounded),
                label: Text(
                  hasData ? 'Share via app' : 'Start server to share',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedDevicesCard extends StatelessWidget {
  const _TrustedDevicesCard({
    required this.devices,
    required this.names,
    required this.onRevoke,
  });

  final List<String> devices;
  final Map<String, String> names;
  final Future<void> Function(String address) onRevoke;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Trusted Hosts',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              devices.isEmpty
                  ? 'No trusted Host yet. A successful pairing will add its local address.'
                  : 'These Hosts can reconnect without entering a new pairing code.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (devices.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...devices.map(
                (address) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.computer_rounded),
                  title: Text(names[address] ?? 'Host device'),
                  subtitle: Text(address),
                  trailing: TextButton(
                    onPressed: () => onRevoke(address),
                    child: const Text('Revoke'),
                  ),
                ),
              ),
            ],
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

  bool get _isValid =>
      value.isNotEmpty && value != 'Not available' && value != 'Loading…';

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
                }
              : null,
        ),
      ],
    );
  }
}

class _AudioReceivingCard extends StatelessWidget {
  const _AudioReceivingCard({
    required this.audioStatus,
    required this.visualizerStream,
  });

  final AudioStreamStatus audioStatus;
  final Stream<Uint8List> visualizerStream;

  @override
  Widget build(BuildContext context) {
    final isReceiving = audioStatus == AudioStreamStatus.receiving;
    final color = Colors.green.shade600;

    return Card(
      color: color.withValues(alpha: .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: .30), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .18),
                  foregroundColor: color,
                  radius: 24,
                  child: const Icon(Icons.graphic_eq_rounded, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Audio receiving',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const Spacer(),
                          if (isReceiving) ...[
                            Icon(
                              Icons.fiber_manual_record,
                              size: 8,
                              color: Colors.red.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        audioStatus.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      const Text('Audio is playing in sync from the Host.'),
                    ],
                  ),
                ),
              ],
            ),
            if (isReceiving) ...[
              const SizedBox(height: 12),
              AudioVisualizer(
                stream: visualizerStream,
                color: color,
                barCount: 30,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
