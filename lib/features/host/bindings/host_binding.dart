import 'package:get/get.dart';

import '../controllers/host_controller.dart';

class HostBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(HostController.new);
}
