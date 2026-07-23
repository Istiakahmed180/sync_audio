import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

enum SetupRole { host, receiver }

class OnboardingController extends GetxController {
  static const _keyOnboardingComplete = 'onboarding_complete';

  final RxInt currentPage = 0.obs;
  int get totalPages => 5;
  final pageController = PageController();
  final selectedRole = Rxn<SetupRole>();
  final wifiCheckMessage = RxnString();
  final isCheckingWifi = false.obs;

  Future<void> checkWifi() async {
    if (isCheckingWifi.value) return;
    isCheckingWifi.value = true;
    wifiCheckMessage.value = null;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final addresses = interfaces
          .expand((interface) => interface.addresses)
          .map((address) => address.address)
          .toList(growable: false);
      wifiCheckMessage.value = addresses.isEmpty
          ? 'No active network found. Connect to Wi‑Fi and try again.'
          : 'Network ready — ${addresses.join(', ')}';
    } catch (_) {
      wifiCheckMessage.value =
          'Could not check the network. Continue with QR or manual setup.';
    } finally {
      isCheckingWifi.value = false;
    }
  }

  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingComplete) ?? false;
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingComplete, true);
  }

  void goToPage(int page) {
    if (page < 0 || page >= totalPages) return;
    currentPage.value = page;
    pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void nextPage() {
    if (currentPage.value < totalPages - 1) {
      goToPage(currentPage.value + 1);
    }
  }

  void previousPage() {
    if (currentPage.value > 0) {
      goToPage(currentPage.value - 1);
    }
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
