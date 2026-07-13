abstract class ConnectionService {
  Future<void> connect({required String ipAddress, required int port});
  Future<void> disconnect();
  bool get isConnected;
}

class PlaceholderConnectionService implements ConnectionService {
  @override
  bool isConnected = false;
  @override
  Future<void> connect({required String ipAddress, required int port}) async {}
  @override
  Future<void> disconnect() async {}
}
