import 'package:get/get.dart';

class ReceiverController extends GetxController {
  final isReceiverRunning = false.obs;
  final isConnectedToHost = false.obs;
  final statusMessage = 'Waiting'.obs;

  void startReceiver() {
    isReceiverRunning.value = true;
    statusMessage.value = 'Receiver active';
  }

  void stopReceiver() {
    isReceiverRunning.value = false;
    statusMessage.value = 'Waiting';
  }
}
