import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../../../models/audio_stream_status.dart';
import '../../../models/connection_status.dart';
import '../../../shared/widgets/app_primary_button.dart';
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
            const SizedBox(height: 20),
            Obx(() => _DetailCard(ipAddress: controller.localIpAddress.value)),
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
                label: 'Last received message',
                value: controller.lastReceivedMessage.value.isEmpty
                    ? 'None yet'
                    : controller.lastReceivedMessage.value,
              ),
            ),
            Obx(
              () => controller.errorMessage.value == null
                  ? const SizedBox.shrink()
                  : _ErrorCard(message: controller.errorMessage.value!),
            ),
            const SizedBox(height: 12),
            const _InfoMessage(
              text:
                  'The receiver accepts one host connection and displays line-delimited test messages over TCP.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.ipAddress});
  final String ipAddress;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _DetailRow(label: 'Local IP address', value: ipAddress),
          const _DetailRow(label: 'Listening port', value: '5050'),
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(title: Text(label), subtitle: Text(value)),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
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
