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
        const SizedBox(height: 24),
        Text(
          'Connection help',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
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
                  'Keep all devices on the same Wi‑Fi network. Start the Receiver first, then use its IP address and required pairing code on the Host.',
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
