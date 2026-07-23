import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/connection_status.dart';
import '../../../models/audio_stream_status.dart';
import '../../../models/receiver_session.dart';
import '../../../app/constants/platform_capabilities.dart';
import '../../../shared/widgets/connection_overview_card.dart';
import '../../../shared/widgets/network_diagnostics_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../controllers/host_controller.dart';
import 'qr_scanner_view.dart';

class HostView extends GetView<HostController> {
  const HostView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.supportsHost) {
      return Scaffold(
        appBar: AppBar(title: const Text('Host Device')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              PlatformCapabilities.hostSupportMessage,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return _HostDiscoveryLifecycle(
      controller: controller,
      child: Scaffold(
        appBar: AppBar(title: const Text('Host Device')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
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
                      'Receiver connection established. You can start system audio.',
                    ConnectionStatus.connecting =>
                      'Connecting to the Receiver. Keep both devices on the same Wi‑Fi network.',
                    _ =>
                      'Enter the Receiver IP and required pairing code to begin.',
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Connect a receiver',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
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
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _ManualSetupSection(controller: controller)),
                ],
              ),
              const SizedBox(height: 12),
              _SavedSpeakerGroupsSection(controller: controller),
              const SizedBox(height: 12),
              _AllReceiverVolumeControl(controller: controller),
              const SizedBox(height: 12),

              Obx(() {
                // Subscribe this receiver list to live diagnostics updates.
                final diagnosticsCount = controller.diagnostics.length;
                final nearbyCount = controller.discoveredDevices.length;
                final addresses = controller.configuredReceiverIps
                    .where(
                      (a) =>
                          controller.receiverPairingControllers.containsKey(a),
                    )
                    .toList();
                if (addresses.isEmpty) {
                  return const _EmptyReceiverState();
                }
                return Column(
                  key: ValueKey('$diagnosticsCount-$nearbyCount'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nearbyCount > 0) ...[
                      Text(
                        'Nearby receivers',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    ...addresses.map((address) {
                      final session = controller.receiverSessionFor(address);
                      final deviceName =
                          session?.deviceName ??
                          controller.discoveredDeviceNames[address];
                      final latencyMs =
                          controller.discoveredDeviceLatencyMs[address];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ReceiverTargetCard(
                          address: address,
                          calibrationMicros: controller.calibrationForReceiver(
                            address,
                          ),
                          deviceName: deviceName,
                          latencyMs: latencyMs,
                          diagnostics: controller.receiverDiagnosticsFor(
                            address,
                          ),
                          isStreaming:
                              controller.audioStatus.value ==
                              AudioStreamStatus.streaming,
                          onRemove: () => controller.removeReceiverIp(address),
                          onRename:
                              session?.controlStatus ==
                                  ControlConnectionStatus.connected
                              ? (name) =>
                                    controller.renameReceiver(address, name)
                              : null,
                          session: session,
                          onConnect: () => controller.connectReceiver(address),
                          onDisconnect: () =>
                              controller.disconnectReceiver(address),
                          onAdjustCalibration: session == null
                              ? null
                              : (delta) => controller.adjustReceiverCalibration(
                                  session,
                                  delta,
                                ),
                        ),
                      );
                    }),
                  ],
                );
              }),
              const SizedBox(height: 12),
              Obx(
                () => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.graphic_eq),
                            const SizedBox(width: 10),
                            Text(
                              'System audio',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            StatusBadge(
                              label: controller.audioStatus.value.label,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          controller.isAudioStreaming
                              ? 'Audio is being sent to the connected Receiver(s).'
                              : 'System audio will start automatically when the Receiver is connected.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Obx(
                () => NetworkDiagnosticsCard(
                  diagnostics: controller.diagnosticsData,
                  isActive: controller.isAudioStreaming,
                ),
              ),
              const SizedBox(height: 4),
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
                () =>
                    controller.isDiscoveryPolling.value ||
                        controller.isDiscoveringReceivers.value
                    ? Text(
                        controller.discoveryStatus.value,
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedSpeakerGroupsSection extends StatelessWidget {
  const _SavedSpeakerGroupsSection({required this.controller});

  final HostController controller;

  Future<void> _saveGroup(BuildContext context) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save speaker group'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'Living Room',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    await controller.saveCurrentAsGroup(name);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.speaker_group_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saved speaker groups',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Save current receivers as a group',
                    onPressed: controller.configuredReceiverIps.isEmpty
                        ? null
                        : () => _saveGroup(context),
                    icon: const Icon(Icons.save_outlined),
                  ),
                ],
              ),
              if (controller.savedGroups.isEmpty)
                Text(
                  'Add receivers first, then save them as a reusable group.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ...controller.savedGroups.map(
                  (group) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.speaker_group_rounded),
                    title: Text(group.name),
                    subtitle: Text(
                      '${group.deviceIps.length} receiver${group.deviceIps.length == 1 ? '' : 's'}',
                    ),
                    onTap: () => controller.applyGroup(group),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Apply group',
                          onPressed: () => controller.applyGroup(group),
                          icon: const Icon(Icons.playlist_play_rounded),
                        ),
                        IconButton(
                          tooltip: 'Delete group',
                          onPressed: () => controller.deleteGroup(group.name),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllReceiverVolumeControl extends StatelessWidget {
  const _AllReceiverVolumeControl({required this.controller});

  final HostController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.volume_up_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All receiver volume',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${(controller.masterReceiverVolume.value * 100).round()}%',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: controller.configuredReceiverIps.isEmpty
                        ? null
                        : controller.toggleMuteAll,
                    icon: Icon(
                      controller.areAllReceiversMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_mute_rounded,
                    ),
                    label: Text(
                      controller.areAllReceiversMuted
                          ? 'Unmute all'
                          : 'Mute all',
                    ),
                  ),
                ],
              ),
              Slider(
                value: controller.masterReceiverVolume.value,
                min: 0,
                max: 1.5,
                divisions: 150,
                label:
                    '${(controller.masterReceiverVolume.value * 100).round()}%',
                onChanged: controller.configuredReceiverIps.isEmpty
                    ? null
                    : controller.setAllReceiverVolumes,
              ),
              Text(
                'Adjusts every configured Receiver together. Individual Receiver controls remain available below.',
                style: Theme.of(context).textTheme.bodySmall,
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
    // Discovery is useful immediately on the Host screen. QR and manual
    // pairing remain available when the network blocks UDP broadcast.
    widget.controller.startDiscoveryPolling(showBusyIndicator: false);
  }

  @override
  void dispose() {
    widget.controller.stopDiscoveryPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ManualSetupSection extends StatefulWidget {
  const _ManualSetupSection({required this.controller});

  final HostController controller;

  @override
  State<_ManualSetupSection> createState() => _ManualSetupSectionState();
}

class _ManualSetupSectionState extends State<_ManualSetupSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.expand_less_rounded : Icons.add_rounded,
            size: 18,
          ),
          label: Text(_expanded ? 'Hide manual setup' : 'Add manually'),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _ManualEntryForm(controller: widget.controller),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _ManualEntryForm extends StatelessWidget {
  const _ManualEntryForm({required this.controller});

  final HostController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Text(
            'Enter the IP address and pairing code shown on the Receiver screen.',
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
        ],
      ),
    );
  }
}

class _ReceiverTargetCard extends StatelessWidget {
  const _ReceiverTargetCard({
    required this.address,
    required this.calibrationMicros,
    required this.onRemove,
    required this.onRename,
    required this.session,
    required this.onConnect,
    required this.onDisconnect,
    this.onAdjustCalibration,
    this.deviceName,
    this.latencyMs,
    this.diagnostics = const <String, Object>{},
    this.isStreaming = false,
  });

  final String address;
  final int calibrationMicros;
  final String? deviceName;
  final int? latencyMs;
  final Map<String, Object> diagnostics;
  final bool isStreaming;
  final VoidCallback onRemove;
  final Future<void> Function(String name)? onRename;
  final ReceiverSession? session;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function(int deltaMilliseconds)? onAdjustCalibration;

  String get _displayName =>
      (deviceName != null && deviceName!.isNotEmpty) ? deviceName! : address;

  Future<void> _rename(BuildContext context) async {
    final nameController = TextEditingController(text: _displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename receiver'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Receiver name',
            hintText: 'Living Room Speaker',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty || onRename == null) return;
    await onRename!(name);
  }

  Widget _signalIndicator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isConnected =
        session?.controlStatus == ControlConnectionStatus.connected;
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
    if (session?.controlStatus == ControlConnectionStatus.connected) {
      return 'Connected';
    }
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
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _PresenceBadge(session: session),
                          const SizedBox(width: 6),
                          _signalIndicator(context),
                          const SizedBox(width: 4),
                          ReceiverNetworkQualityBadge(
                            diagnostics: diagnostics,
                            isActive: isStreaming,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _signalLabel(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                      if (deviceName != null && deviceName!.isNotEmpty)
                        Text(
                          address,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rename receiver',
                  onPressed: onRename == null ? null : () => _rename(context),
                  icon: const Icon(Icons.edit_outlined),
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
            const SizedBox(height: 6),
            _CalibrationControls(
              calibrationMicros: calibrationMicros,
              onAdjust: onAdjustCalibration,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceBadge extends StatelessWidget {
  const _PresenceBadge({required this.session});

  final ReceiverSession? session;

  @override
  Widget build(BuildContext context) {
    final status = session?.controlStatus;
    final isOnline = status == ControlConnectionStatus.connected;
    final isConnecting =
        status == ControlConnectionStatus.connecting ||
        status == ControlConnectionStatus.reconnecting;
    final color = isOnline
        ? Colors.green
        : isConnecting
        ? Colors.orange
        : Theme.of(context).colorScheme.error;
    final label = isOnline
        ? 'Online'
        : isConnecting
        ? 'Connecting'
        : 'Offline';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibrationControls extends StatelessWidget {
  const _CalibrationControls({
    required this.calibrationMicros,
    required this.onAdjust,
  });

  final int calibrationMicros;
  final Future<void> Function(int deltaMilliseconds)? onAdjust;

  String get _valueLabel {
    final milliseconds = calibrationMicros / 1000;
    final formatted = milliseconds == milliseconds.roundToDouble()
        ? milliseconds.toStringAsFixed(0)
        : milliseconds.toStringAsFixed(1);
    return '${milliseconds > 0 ? '+' : ''}$formatted ms';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onAdjust != null;
    return Row(
      children: [
        Icon(
          Icons.tune_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            enabled ? 'Delay adjustment: $_valueLabel' : 'Delay adjustment',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'Reduce delay by 10 ms',
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onAdjust!(-10) : null,
          icon: const Icon(Icons.fast_rewind_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'Reduce delay by 1 ms',
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onAdjust!(-1) : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'Reset delay adjustment',
          visualDensity: VisualDensity.compact,
          onPressed: enabled && calibrationMicros != 0
              ? () => onAdjust!(-(calibrationMicros / 1000).round())
              : null,
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'Increase delay by 1 ms',
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onAdjust!(1) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
        IconButton(
          tooltip: 'Increase delay by 10 ms',
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onAdjust!(10) : null,
          icon: const Icon(Icons.fast_forward_rounded, size: 18),
        ),
      ],
    );
  }
}

class _EmptyReceiverState extends StatelessWidget {
  const _EmptyReceiverState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              Icons.speaker_group_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No receivers added yet. Scan a QR code or add one manually.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
