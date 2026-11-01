import 'message_protocol.dart';

/// One framed TCP connection to a peer.
abstract interface class PeerConnection {
  /// Null until the connection is authenticated against a paired identity.
  /// Request handlers must use this, never `MessageEnvelope.senderNodeId`.
  String? get authenticatedNodeId;

  Stream<MessageEnvelope> get messages;
  Future<void> send(MessageEnvelope message);
  Future<void> close();
}

/// Outbound connections (PRD §5.3). Should use TLS with public-key pinning or
/// an equivalent authenticated channel once pairing is designed (FR-09).
abstract interface class SocketClient {
  Future<PeerConnection> connect(String host, int port);
}

class UnimplementedSocketClient implements SocketClient {
  const UnimplementedSocketClient();

  @override
  Future<PeerConnection> connect(String host, int port) =>
      throw UnimplementedError('SocketClient: Milestone 2');
}
