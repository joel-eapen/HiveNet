import 'dart:typed_data';

import 'message_protocol.dart';

/// Length-prefixed framing over TCP (PRD FR-08, Milestone 3). One socket read
/// is never assumed to equal one message: the decoder must buffer partial
/// frames and split coalesced ones, and reject frames above `maxFrameBytes`
/// with `HiveErrorCode.oversizedMessage`.
abstract interface class MessageFraming {
  Uint8List encode(MessageEnvelope message);

  /// Transforms a raw byte stream into complete messages.
  Stream<MessageEnvelope> decode(Stream<List<int>> bytes);
}

class UnimplementedMessageFraming implements MessageFraming {
  const UnimplementedMessageFraming();

  @override
  Uint8List encode(MessageEnvelope message) =>
      throw UnimplementedError('MessageFraming: Milestone 3');

  @override
  Stream<MessageEnvelope> decode(Stream<List<int>> bytes) =>
      throw UnimplementedError('MessageFraming: Milestone 3');
}
