import 'dart:io';

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
              Platform.isAndroid
                  ? 'Use this Android device as the Host or Receiver on the same Wi‑Fi network.'
                  : 'Use this computer as the Host and connect one or more Android Receivers on the same Wi‑Fi network.',
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
              description: Platform.isAndroid
                  ? 'Capture and send audio to all Receivers.'
                  : 'Capture computer audio and send it to Android Receivers.',
              icon: Icons.wifi_tethering_rounded,
              onTap: () => Get.toNamed(AppRoutes.host),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              ModeSelectionCard(
                title: 'Receiver Device',
                description:
                    'Join as a speaker — play the Host\'s audio in sync.',
                icon: Icons.speaker_group_rounded,
                onTap: () => Get.toNamed(AppRoutes.receiver),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
