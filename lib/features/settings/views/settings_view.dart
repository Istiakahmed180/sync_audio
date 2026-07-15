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
        _ThemeSelector(controller: controller),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Scheduled Streaming'),
        const SizedBox(height: 12),
        _ScheduledStreamingCard(controller: controller),
        const SizedBox(height: 24),
        _sectionTitle(context, 'About'),
        const SizedBox(height: 12),
        _SettingRow(label: 'Version', value: AppConstants.appVersion),
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
  Widget build(BuildContext context) => Obx(
    () => Card(
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
    ),
  );
}

class _ScheduledStreamingCard extends StatelessWidget {
  const _ScheduledStreamingCard({required this.controller});
  final SettingsController controller;
  @override
  Widget build(BuildContext context) => Obx(
    () => Card(
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
