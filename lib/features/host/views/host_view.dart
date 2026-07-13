import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/app_primary_button.dart';
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
                  'Host status',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Obx(
                  () => StatusBadge(
                    label: controller.isStreaming.value
                        ? 'Streaming'
                        : controller.isConnected.value
                        ? 'Connected'
                        : 'Not Connected',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _InfoCard(
              label: 'Connected receivers',
              value: controller.connectedDeviceCount,
              icon: Icons.devices_other_rounded,
            ),
            const SizedBox(height: 12),
            Obx(
              () => _InfoCard(
                label: 'Streaming status',
                value: controller.isStreaming.value
                    ? 'Active'.obs
                    : 'Inactive'.obs,
                icon: Icons.graphic_eq_rounded,
              ),
            ),
            const SizedBox(height: 24),
            AppPrimaryButton(
              label: 'Find Receiver',
              icon: Icons.search_rounded,
              onPressed: controller.findReceiver,
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Start Streaming',
                icon: Icons.play_arrow_rounded,
                onPressed: controller.isConnected.value ? () {} : null,
              ),
            ),
            const SizedBox(height: 24),
            const _InfoMessage(
              text:
                  'Networking, receiver discovery, and audio streaming will be implemented in a later phase.',
            ),
            Obx(
              () => Text(
                controller.statusMessage.value,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final Rx<dynamic> value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(child: Text(label)),
            Obx(
              () => Text(
                '${value.value}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
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
