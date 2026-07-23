import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingController extends GetxController {
  static const _keyOnboardingComplete = 'onboarding_complete';

  final RxInt currentPage = 0.obs;
  int get totalPages => 4;
  final pageController = PageController();

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
