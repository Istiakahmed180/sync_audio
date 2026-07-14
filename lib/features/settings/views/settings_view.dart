import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionTitle(context, 'Appearance'),
        const SizedBox(height: 12),
        Obx(() => _ThemeSelector(controller: controller)),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Scheduled Streaming'),
        const SizedBox(height: 12),
        Obx(() => _ScheduledStreamingCard(controller: controller)),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Usage Statistics'),
        const SizedBox(height: 12),
        Obx(() => _UsageStatsCard(controller: controller)),
        const SizedBox(height: 24),
        _sectionTitle(context, 'About'),
        const SizedBox(height: 12),
        _SettingRow(label: 'Version', value: AppConstants.appVersion),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Connection Help'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before connecting',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Keep all devices on the same Wi‑Fi network. Start the Receiver first, then use its IP address and pairing code on the Host.',
                ),
                const SizedBox(height: 12),
                Text(
                  'If connection fails',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Check the IP, port, and pairing code. The Host Connect button becomes available again after a failed attempt.',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
  );
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.controller});
  final SettingsController controller;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: ThemeMode.values.map((mode) {
          final selected = controller.themeMode.value == mode;
          return ChoiceChip(
            label: Text(mode.name[0].toUpperCase() + mode.name.substring(1)),
            selected: selected,
            onSelected: (_) => controller.setThemeMode(mode),
          );
        }).toList(),
      ),
    ),
  );
}

class _ScheduledStreamingCard extends StatelessWidget {
  const _ScheduledStreamingCard({required this.controller});
  final SettingsController controller;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Enable scheduled streaming'),
            subtitle: const Text('Auto start/stop audio at set times'),
            value: controller.isScheduledEnabled.value,
            onChanged: controller.setScheduleEnabled,
            contentPadding: EdgeInsets.zero,
          ),
          if (controller.isScheduledEnabled.value) ...[
            const Divider(),
            _TimePickerRow(
              label: 'Start time',
              hour: controller.scheduleStartHour,
              minute: controller.scheduleStartMinute,
              onChanged: controller.scheduleStartTime,
            ),
            const SizedBox(height: 12),
            _TimePickerRow(
              label: 'Stop time',
              hour: controller.scheduleStopHour,
              minute: controller.scheduleStopMinute,
              onChanged: controller.scheduleStopTime,
            ),
          ],
        ],
      ),
    ),
  );
}

class _TimePickerRow extends StatelessWidget {
  const _TimePickerRow({
    required this.label,
    required this.hour,
    required this.minute,
    required this.onChanged,
  });
  final String label;
  final RxInt hour;
  final RxInt minute;
  final void Function(int h, int m) onChanged;

  Future<void> _pickTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour.value, minute: minute.value),
    );
    if (time != null) onChanged(time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label),
      TextButton.icon(
        onPressed: () => _pickTime(context),
        icon: const Icon(Icons.access_time, size: 18),
        label: Text(
          '${hour.value.toString().padLeft(2, '0')}:${minute.value.toString().padLeft(2, '0')}',
        ),
      ),
    ],
  );
}

class _UsageStatsCard extends StatelessWidget {
  const _UsageStatsCard({required this.controller});
  final SettingsController controller;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _StatRow(
            label: 'Total stream time',
            value: _formatMinutes(controller.totalStreamTimeMinutes.value),
          ),
          const Divider(),
          _StatRow(
            label: 'Data sent',
            value: '${controller.totalDataSentMb.value.toStringAsFixed(1)} MB',
          ),
          const Divider(),
          _StatRow(
            label: 'Packets lost',
            value: '${controller.totalPacketsLost.value}',
          ),
        ],
      ),
    ),
  );

  static String _formatMinutes(int mins) {
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}
