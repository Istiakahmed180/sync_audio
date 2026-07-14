import 'package:flutter/material.dart';
import 'package:get/get.dart';

void showAppErrorSnackbar(String message) {
  if (message.trim().isEmpty || Get.context == null) return;
  if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
  Get.snackbar(
    'Error',
    message,
    snackPosition: SnackPosition.TOP,
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    borderRadius: 12,
    backgroundColor: Get.theme.colorScheme.errorContainer,
    colorText: Get.theme.colorScheme.onErrorContainer,
    icon: Icon(
      Icons.error_outline,
      color: Get.theme.colorScheme.onErrorContainer,
    ),
    duration: const Duration(seconds: 4),
    isDismissible: true,
  );
}
