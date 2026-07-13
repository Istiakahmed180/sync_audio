import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/audio_stream_status.dart';
import '../../../models/connection_status.dart';
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
                  'Connection status',
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
            TextField(
              controller: controller.receiverIpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Receiver IP address',
                hintText: '192.168.1.10, 192.168.1.11',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '5050',
              ),
            ),
            const SizedBox(height: 16),
            Obx(
              () => AppPrimaryButton(
                label: controller.isConnecting ? 'Connecting…' : 'Connect',
                icon: Icons.link_rounded,
                isLoading: controller.isConnecting,
                onPressed: controller.isConnecting || controller.isConnected
                    ? null
                    : controller.connect,
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Disconnect',
                icon: Icons.link_off_rounded,
                onPressed: controller.isConnected
                    ? controller.disconnect
                    : null,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Test message',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.testMessageController,
              enabled: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Message to send'),
            ),
            const SizedBox(height: 16),
            Obx(
              () => AppPrimaryButton(
                label: 'Send Test Message',
                icon: Icons.send_rounded,
                onPressed: controller.isConnected
                    ? controller.sendTestMessage
                    : null,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'System audio',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Capture supported app playback through Android MediaProjection and send it over UDP.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.audioPortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Audio UDP port',
                hintText: '5051',
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Audio status'),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${controller.receiverCount.value} receivers'),
                      const SizedBox(width: 10),
                      StatusBadge(label: controller.audioStatus.value.label),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Start System Audio',
                icon: Icons.graphic_eq_rounded,
                onPressed:
                    controller.audioStatus.value == AudioStreamStatus.streaming
                    ? null
                    : controller.startSystemAudioStream,
              ),
            ),
            const SizedBox(height: 12),
            Obx(
              () => AppPrimaryButton(
                label: 'Stop System Audio',
                icon: Icons.stop_circle_outlined,
                onPressed:
                    controller.audioStatus.value == AudioStreamStatus.streaming
                    ? controller.stopSystemAudioStream
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            Obx(
              () => _MessageCard(
                label: 'Last sent message',
                value: controller.lastSentMessage.value.isEmpty
                    ? 'None yet'
                    : controller.lastSentMessage.value,
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
                  'Phase 4 captures microphone PCM on Android and forwards it over the existing local Wi-Fi UDP audio path.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(value),
        ],
      ),
    ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
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
