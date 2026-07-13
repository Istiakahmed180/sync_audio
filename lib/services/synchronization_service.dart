abstract class SynchronizationService {
  Future<void> synchronize();
  Future<void> stop();
  bool get isSynchronizing;
}

class PlaceholderSynchronizationService implements SynchronizationService {
  @override
  bool isSynchronizing = false;
  @override
  Future<void> synchronize() async {}
  @override
  Future<void> stop() async {}
}
