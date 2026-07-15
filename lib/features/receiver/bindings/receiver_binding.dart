import 'package:get/get.dart';

import '../controllers/receiver_controller.dart';

class ReceiverBinding extends Bindings {
  @override
  void dependencies() {
    // The receiver keeps serving audio after its screen is popped.
    if (!Get.isRegistered<ReceiverController>()) {
      Get.put(ReceiverController(), permanent: true);
    }
  }
}
