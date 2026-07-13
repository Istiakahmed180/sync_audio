import 'package:get/get.dart';

import '../controllers/receiver_controller.dart';

class ReceiverBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(ReceiverController.new);
}
