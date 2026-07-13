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
        Text(
          'Device',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Obx(
          () => _SettingTile(
            label: 'Device name',
            value: controller.deviceName.value,
          ),
        ),
        Obx(
          () => _SettingTile(
            label: 'Default device mode',
            value: controller.deviceMode.value,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Preferences',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Obx(
          () => _SettingTile(
            label: 'Theme mode',
            value: controller.themeMode.value,
          ),
        ),
        Obx(
          () => _SettingTile(
            label: 'Audio quality',
            value: controller.audioQuality.value,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'About',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _SettingTile(label: 'Version', value: AppConstants.appVersion),
      ],
    ),
  );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.label, required this.value});
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
