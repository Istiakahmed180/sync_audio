import 'package:get/get.dart';

class HostController extends GetxController {
  final isConnected = false.obs;
  final isStreaming = false.obs;
  final connectedDeviceCount = 0.obs;
  final statusMessage = 'Not connected'.obs;

  void findReceiver() => statusMessage.value = 'Ready to find receivers';
}
