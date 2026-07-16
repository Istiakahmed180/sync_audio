import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle(context, 'Basic'),
          const SizedBox(height: 12),
          _ThemeSelector(controller: controller),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Advanced'),
          const SizedBox(height: 12),
          _AdvancedSettingsCard(controller: controller),
          const SizedBox(height: 24),
          _sectionTitle(context, 'About'),
          const SizedBox(height: 12),
          _SettingRow(label: 'Version', value: AppConstants.appVersion),
          const SizedBox(height: 8),
          Obx(
            () => _SettingRow(
              label: 'Total stream time',
              value: _formatMinutes(controller.totalStreamTimeMinutes.value),
            ),
          ),
          const SizedBox(height: 8),
          Obx(
            () => _SettingRow(
              label: 'Data sent',
              value: '${controller.totalDataSentMb.value.toStringAsFixed(1)} MB',
            ),
          ),
          const SizedBox(height: 8),
          Obx(
            () => _SettingRow(
              label: 'Packets lost',
              value: '${controller.totalPacketsLost.value}',
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h h $m min';
  }

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ThemeMode.values.map((mode) {
                final selected = controller.themeMode.value == mode;
                return ChoiceChip(
                  label: Text(
                    mode.name[0].toUpperCase() + mode.name.substring(1),
                  ),
                  selected: selected,
                  onSelected: (_) => controller.setThemeMode(mode),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AdvancedSettingsCard extends StatefulWidget {
  const _AdvancedSettingsCard({required this.controller});
  final SettingsController controller;

  @override
  State<_AdvancedSettingsCard> createState() => _AdvancedSettingsCardState();
}

class _AdvancedSettingsCardState extends State<_AdvancedSettingsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Scheduled streaming'),
            subtitle: Obx(
              () => Text(
                widget.controller.isScheduledEnabled.value
                    ? 'On — audio starts/stops automatically'
                    : 'Off',
              ),
            ),
            trailing: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _ScheduledStreamingContent(controller: widget.controller),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _ScheduledStreamingContent extends StatelessWidget {
  const _ScheduledStreamingContent({required this.controller});
  final SettingsController controller;

  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      children: [
        const Divider(height: 1),
        Padding(
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
      ],
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
