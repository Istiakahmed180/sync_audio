enum ControlCommandType {
  hello,
  helloAck,
  ping,
  pong,
  streamPrepare,
  streamStart,
  streamStop,
  setPlaybackOffset,
  bufferStatus,
  error,
}

extension ControlCommandTypeWireName on ControlCommandType {
  String get wireName => switch (this) {
    ControlCommandType.hello => 'HELLO',
    ControlCommandType.helloAck => 'HELLO_ACK',
    ControlCommandType.ping => 'PING',
    ControlCommandType.pong => 'PONG',
    ControlCommandType.streamPrepare => 'STREAM_PREPARE',
    ControlCommandType.streamStart => 'STREAM_START',
    ControlCommandType.streamStop => 'STREAM_STOP',
    ControlCommandType.setPlaybackOffset => 'SET_PLAYBACK_OFFSET',
    ControlCommandType.bufferStatus => 'BUFFER_STATUS',
    ControlCommandType.error => 'ERROR',
  };

  static ControlCommandType? parse(String value) {
    for (final type in ControlCommandType.values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

class ControlCommand {
  const ControlCommand({required this.type, required this.arguments});

  final ControlCommandType type;
  final List<String> arguments;

  String get line => [type.wireName, ...arguments].join(':');

  static ControlCommand? parse(String line) {
    final fields = line.trim().split(':');
    final type = ControlCommandTypeWireName.parse(fields.first);
    if (type == null) return null;
    final arguments = fields.skip(1).toList(growable: false);
    if (!_hasValidArgumentCount(type, arguments.length)) return null;
    return ControlCommand(type: type, arguments: arguments);
  }

  static bool _hasValidArgumentCount(ControlCommandType type, int count) =>
      switch (type) {
        ControlCommandType.helloAck => count == 1,
        ControlCommandType.hello => count == 1 || count == 2,
        ControlCommandType.ping => count == 2,
        ControlCommandType.pong => count == 3,
        ControlCommandType.streamPrepare ||
        ControlCommandType.streamStart => count >= 2 && count <= 4,
        ControlCommandType.streamStop => count == 1,
        ControlCommandType.setPlaybackOffset => count == 1,
        ControlCommandType.bufferStatus => count == 2,
        ControlCommandType.error => count >= 2,
      };
}

class ControlEvent {
  const ControlEvent({required this.sourceId, required this.command});

  final String sourceId;
  final ControlCommand command;
}
