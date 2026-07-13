import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../controllers/receiver_controller.dart';

class ReceiverView extends GetView<ReceiverController> {
  const ReceiverView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receiver Device')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Receiver status',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Obx(
                () => StatusBadge(
                  label: controller.statusMessage.value == 'Waiting'
                      ? 'Waiting'
                      : 'Connected',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                children: [
                  _DetailRow(label: 'Device name', value: 'This device'),
                  _DetailRow(label: 'Host IP address', value: 'Not available'),
                  _DetailRow(
                    label: 'Port',
                    value: '${AppConstants.placeholderPort}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Obx(
            () => AppPrimaryButton(
              label: 'Start Receiver',
              icon: Icons.play_arrow_rounded,
              onPressed: controller.isReceiverRunning.value
                  ? null
                  : controller.startReceiver,
            ),
          ),
          const SizedBox(height: 12),
          Obx(
            () => AppPrimaryButton(
              label: 'Stop Receiver',
              icon: Icons.stop_rounded,
              onPressed: controller.isReceiverRunning.value
                  ? controller.stopReceiver
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          const _InfoMessage(
            text:
                'The receiver server and host connection will be implemented in a later phase.',
          ),
        ],
      ),
    ),
  );
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
