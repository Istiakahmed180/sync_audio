import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../controllers/onboarding_controller.dart';

class OnboardingView extends GetView<OnboardingController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildSkipButton(context),
            Expanded(
              child: PageView(
                controller: controller.pageController,
                onPageChanged: (page) => controller.currentPage.value = page,
                children: [
                  _WelcomePage(scheme: scheme),
                  _HostPage(scheme: scheme),
                  _ReceiverPage(scheme: scheme),
                  _ReadyPage(scheme: scheme),
                ],
              ),
            ),
            _buildBottomNav(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Obx(() {
        if (controller.currentPage.value == controller.totalPages - 1) {
          return const SizedBox(height: 48);
        }
        return TextButton(
          onPressed: () => _finishOnboarding(),
          child: const Text('Skip'),
        );
      }),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        children: [
          Obx(() {
            return Row(
              children: List.generate(
                controller.totalPages,
                (i) => _PageIndicator(
                  isActive: i == controller.currentPage.value,
                  scheme: Theme.of(context).colorScheme,
                ),
              ),
            );
          }),
          const Spacer(),
          Obx(() {
            final isLast = controller.currentPage.value == controller.totalPages - 1;
            if (isLast) {
              return AppPrimaryButton(
                label: 'Get Started',
                icon: Icons.check_rounded,
                onPressed: () => _finishOnboarding(),
              );
            }
            return AppPrimaryButton(
              label: 'Next',
              onPressed: () => controller.nextPage(),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    await controller.completeOnboarding();
    Get.offAllNamed(AppRoutes.home);
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.isActive, required this.scheme});

  final bool isActive;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(right: 8),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? scheme.primary : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.multitrack_audio_rounded,
              size: 52,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to\nSync Audio',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Turn multiple devices into a synchronized speaker system. '
            'Play music on one Android phone and hear it from every '
            'other device at the same time.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostPage extends StatelessWidget {
  const _HostPage({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              size: 48,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Host — send audio',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'The Host is the device that has the audio you want to share — '
              'like music, a video, or a podcast. It captures whatever is '
              'playing and sends it to every Receiver at the same time.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.android_rounded,
            text: 'Android only — captures system audio from any app',
            scheme: scheme,
          ),
          const SizedBox(height: 8),
          _FeatureItem(
            icon: Icons.wifi_rounded,
            text: 'Sends audio over your local Wi‑Fi network',
            scheme: scheme,
          ),
          const SizedBox(height: 8),
          _FeatureItem(
            icon: Icons.pin_rounded,
            text: 'Shows a pairing code that Receivers use to connect',
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

class _ReceiverPage extends StatelessWidget {
  const _ReceiverPage({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.speaker_group_rounded,
              size: 48,
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Receiver — play audio',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Receivers are the speakers — any other phone, tablet, or '
              'computer that plays back the Host\'s audio. You can connect '
              'as many Receivers as you want, and they all stay in sync.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.devices_rounded,
            text: 'Works on Android, iOS, macOS, Windows, and Linux',
            scheme: scheme,
          ),
          const SizedBox(height: 8),
          _FeatureItem(
            icon: Icons.qr_code_rounded,
            text: 'The Host scans your QR code, or you share the pairing code',
            scheme: scheme,
          ),
          const SizedBox(height: 8),
          _FeatureItem(
            icon: Icons.sync_rounded,
            text: 'Plays audio in sync — all Receivers stay together',
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

class _ReadyPage extends StatelessWidget {
  const _ReadyPage({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 52,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'You\'re all set!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _ReadyTip(
                  icon: Icons.wifi_rounded,
                  text: 'Connect all devices to the same Wi‑Fi network',
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ReadyTip(
                  icon: Icons.wifi_tethering_rounded,
                  text: 'On your Android phone, tap "Host Device" to start sharing audio',
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ReadyTip(
                  icon: Icons.speaker_group_rounded,
                  text: 'On every other device, tap "Receiver Device" to join',
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ReadyTip(
                  icon: Icons.qr_code_rounded,
                  text: 'The Host scans your QR code to connect',
                  scheme: scheme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({required this.icon, required this.text, required this.scheme});

  final IconData icon;
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _ReadyTip extends StatelessWidget {
  const _ReadyTip({required this.icon, required this.text, required this.scheme});

  final IconData icon;
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
