import 'socket_client.dart';

/// Inbound TCP listener (PRD §5.3). Foreground-first: it must stop cleanly
/// when the OS requires it, and the device is advertised as ready only after
/// local state is restored (PRD §10.5).
abstract interface class SocketServer {
  Stream<PeerConnection> get connections;

  /// Starts listening and returns the bound port. Pass 0 for any free port.
  Future<int> start({int port = 0});
  Future<void> stop();
}

class UnimplementedSocketServer implements SocketServer {
  const UnimplementedSocketServer();

  @override
  Stream<PeerConnection> get connections => const Stream.empty();

  @override
  Future<int> start({int port = 0}) =>
      throw UnimplementedError('SocketServer: Milestone 2');

  @override
  Future<void> stop() async {}
}
