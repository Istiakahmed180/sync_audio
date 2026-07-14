import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/mode_selection_card.dart';
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Get.toNamed(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Synchronized audio,\nsimplified.',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Use one Android device as the Host and one or more devices as Receivers on the same Wi‑Fi network.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            Text(
              'Choose a role',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ModeSelectionCard(
              title: 'Host Device',
              description: 'Send audio to connected receiver devices.',
              icon: Icons.wifi_tethering_rounded,
              onTap: () => Get.toNamed(AppRoutes.host),
            ),
            const SizedBox(height: 12),
            ModeSelectionCard(
              title: 'Receiver Device',
              description: 'Receive and play audio from a host device.',
              icon: Icons.speaker_group_rounded,
              onTap: () => Get.toNamed(AppRoutes.receiver),
            ),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Quick start\n1. Start Receiver on the speaker devices.\n2. Copy a Receiver IP address and pairing code.\n3. Open Host, enter those details, and connect.\n4. Start system audio after the connection is ready.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
