import 'package:get/get.dart';

import '../controllers/host_controller.dart';

class HostBinding extends Bindings {
  @override
  void dependencies() {
    // The host connection/stream is independent of the Host screen.
    if (!Get.isRegistered<HostController>()) {
      Get.put(HostController(), permanent: true);
    }
  }
}
