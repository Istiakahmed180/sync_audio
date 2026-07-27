import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_primary_button.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../controllers/onboarding_controller.dart';
import '../../../services/device_info_service.dart';

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
              child: ResponsiveContent(
                maxWidth: 760,
                child: PageView(
                  controller: controller.pageController,
                  onPageChanged: (page) => controller.currentPage.value = page,
                  children: [
                    _AdaptiveOnboardingPage(
                      child: _WelcomePage(scheme: scheme),
                    ),
                    _AdaptiveOnboardingPage(child: _HostPage(scheme: scheme)),
                    _AdaptiveOnboardingPage(
                      child: _ReceiverPage(scheme: scheme),
                    ),
                    _AdaptiveOnboardingPage(
                      child: _PermissionSetupPage(scheme: scheme),
                    ),
                    _AdaptiveOnboardingPage(child: _ReadyPage(scheme: scheme)),
                    _AdaptiveOnboardingPage(
                      child: _SetupPage(controller: controller, scheme: scheme),
                    ),
                  ],
                ),
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
            final isLast =
                controller.currentPage.value == controller.totalPages - 1;
            if (isLast && controller.selectedRole.value != null) {
              return AppPrimaryButton(
                label: 'Start setup',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => _openSetup(),
              );
            }
            if (isLast) {
              return AppPrimaryButton(
                label: 'Open app',
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

  Future<void> _openSetup() async {
    await controller.completeOnboarding();
    final route = controller.selectedRole.value == SetupRole.receiver
        ? AppRoutes.receiver
        : AppRoutes.host;
    Get.offAllNamed(route);
  }
}

class _AdaptiveOnboardingPage extends StatelessWidget {
  const _AdaptiveOnboardingPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
      child: child,
    ),
  );
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
            'Welcome to\nSyncMesh Audio',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Turn multiple devices into a synchronized speaker system. '
            'Play music on one Android phone and hear it from every '
            'other device at the same time.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
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
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
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
            text: 'Host works on Android, macOS, and Windows',
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
            text: 'Connects to Receivers using their QR code or pairing code',
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
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
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
            text: 'Receivers can run on Android, iOS, macOS, and Windows',
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

class _PermissionSetupPage extends StatelessWidget {
  const _PermissionSetupPage({required this.scheme});

  final ColorScheme scheme;

  List<_PermissionStepData> get _steps {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const [
          _PermissionStepData(
            icon: Icons.mic_rounded,
            title: 'Allow microphone access',
            details:
                'Settings → Apps → SyncMesh Audio → Permissions → Microphone → Allow while using the app.',
          ),
          _PermissionStepData(
            icon: Icons.location_on_rounded,
            title: 'Allow location while using the app',
            details:
                'Location access lets Android reveal the connected Wi‑Fi name for discovery and network diagnostics.',
          ),
          _PermissionStepData(
            icon: Icons.notifications_rounded,
            title: 'Allow notifications',
            details:
                'Notifications keep background streaming status and media controls available when the app is minimized.',
          ),
        ];
      case TargetPlatform.macOS:
        return const [
          _PermissionStepData(
            icon: Icons.screen_share_rounded,
            title: 'Allow Screen & System Audio Recording',
            details:
                'System Settings → Privacy & Security → Screen & System Audio Recording → enable SyncMesh Audio, then restart the app.',
          ),
          _PermissionStepData(
            icon: Icons.mic_rounded,
            title: 'Allow Microphone if mixing mic audio',
            details:
                'Enable SyncMesh Audio under Privacy & Security → Microphone when microphone mixing or calibration is needed.',
          ),
          _PermissionStepData(
            icon: Icons.wifi_rounded,
            title: 'Keep Local Network available',
            details:
                'Allow local network access if macOS asks, so Host and Receiver discovery can work on the same Wi‑Fi.',
          ),
        ];
      case TargetPlatform.windows:
        return const [
          _PermissionStepData(
            icon: Icons.mic_rounded,
            title: 'Allow microphone access',
            details:
                'Settings → Privacy & security → Microphone → enable microphone access for desktop apps.',
          ),
          _PermissionStepData(
            icon: Icons.volume_up_rounded,
            title: 'Choose a Windows audio output',
            details:
                'Select the speakers or headphones you want the Receiver to use, and keep the device enabled in Sound settings.',
          ),
          _PermissionStepData(
            icon: Icons.security_rounded,
            title: 'Allow Private network access',
            details:
                'When Windows Firewall asks, allow SyncMesh Audio on Private networks so discovery and audio control can reach other devices.',
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        children: [
          Icon(Icons.verified_user_rounded, size: 54, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'Permission setup',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete these steps before starting audio so pairing and background streaming work reliably.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          for (var index = 0; index < steps.length; index++) ...[
            _PermissionStep(
              number: index + 1,
              data: steps[index],
              scheme: scheme,
            ),
            if (index != steps.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => DeviceInfoService().openPlatformSettings(),
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open platform settings'),
          ),
          const SizedBox(height: 8),
          Text(
            'After changing permissions, return to SyncMesh Audio and continue setup.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PermissionStepData {
  const _PermissionStepData({
    required this.icon,
    required this.title,
    required this.details,
  });

  final IconData icon;
  final String title;
  final String details;
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.number,
    required this.data,
    required this.scheme,
  });

  final int number;
  final _PermissionStepData data;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text('$number'),
            ),
            const SizedBox(width: 12),
            Icon(data.icon, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(data.details),
                ],
              ),
            ),
          ],
        ),
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
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
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
                  text: 'Tap "Host Device" to start sharing audio',
                  scheme: scheme,
                ),
                const SizedBox(height: 12),
                _ReadyTip(
                  icon: Icons.speaker_group_rounded,
                  text: 'On another device, tap "Receiver Device" to join',
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

class _SetupPage extends StatelessWidget {
  const _SetupPage({required this.controller, required this.scheme});

  final OnboardingController controller;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Obx(
        () => Column(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 54, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Set up SyncMesh Audio',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose what this device will do, then follow the guided setup.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            SegmentedButton<SetupRole>(
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(
                  value: SetupRole.host,
                  icon: Icon(Icons.wifi_tethering_rounded),
                  label: Text('Host'),
                ),
                ButtonSegment(
                  value: SetupRole.receiver,
                  icon: Icon(Icons.speaker_group_rounded),
                  label: Text('Receiver'),
                ),
              ],
              selected: controller.selectedRole.value == null
                  ? const <SetupRole>{}
                  : {controller.selectedRole.value!},
              onSelectionChanged: (selection) {
                controller.selectedRole.value = selection.first;
              },
            ),
            const SizedBox(height: 18),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.wifi_rounded),
                    title: const Text('Use the same Wi‑Fi'),
                    subtitle: Text(
                      controller.wifiCheckMessage.value ??
                          'Check before pairing devices.',
                    ),
                    trailing: controller.isCheckingWifi.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'Check Wi‑Fi',
                            onPressed: controller.checkWifi,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_rounded),
                    title: Text(
                      controller.selectedRole.value == SetupRole.receiver
                          ? 'Start Receiver and share the QR code'
                          : 'Scan a Receiver QR code or add it manually',
                    ),
                    subtitle: const Text(
                      'The pairing code verifies the device.',
                    ),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.graphic_eq_rounded),
                    title: Text('Test before streaming'),
                    subtitle: Text(
                      'Run Test network, then start audio and verify sound at the Receiver.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              controller.selectedRole.value == null
                  ? 'Select a role to continue.'
                  : controller.selectedRole.value == SetupRole.receiver
                  ? 'Next: start the Receiver server and keep the QR code visible for pairing.'
                  : 'Next: add a Receiver, verify the pairing code, then run a network test.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.text,
    required this.scheme,
  });

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
  const _ReadyTip({
    required this.icon,
    required this.text,
    required this.scheme,
  });

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
