import 'dart:async';
import 'dart:io';

import '../security/device_identity.dart';
import '../security/secure_channel.dart';

/// Listens for peers and turns each connection into an authenticated
/// [SecureChannel] before anything else sees it (PRD FR-01, section 5.3).
///
/// A connection that fails authentication is dropped silently: it never
/// reaches [onChannel], and one bad peer cannot affect the others.
class PeerServer {
  PeerServer({
    required this.identity,
    required this.signer,
    required this.verifier,
    required this.onChannel,
    this.allowUnknown = _never,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.maxPendingHandshakes = 16,
  });

  final DeviceIdentity identity;
  final DeviceIdentityService signer;
  final PeerVerifier verifier;
  final void Function(SecureChannel channel) onChannel;

  /// Asked for every connection. True only while a pairing invite is active,
  /// so unknown devices can connect to pair and at no other time.
  final bool Function() allowUnknown;

  static bool _never() => false;
  final Duration handshakeTimeout;

  /// Handshakes allowed at once. Stops an unauthenticated flood from using up
  /// memory and CPU.
  final int maxPendingHandshakes;

  ServerSocket? _server;
  int _pending = 0;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  Future<int> start({int port = 0, InternetAddress? address}) async {
    if (_server != null) return _server!.port;
    final server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_accept, onError: (_) {});
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
  }

  Future<void> _accept(Socket socket) async {
    if (_pending >= maxPendingHandshakes) {
      socket.destroy();
      return;
    }
    _pending++;
    try {
      final channel = await SecureChannel.accept(
        socket,
        identity: identity,
        signer: signer,
        verifier: verifier,
        allowUnknown: allowUnknown(),
        timeout: handshakeTimeout,
      );
      onChannel(channel);
    } catch (_) {
      // Unauthenticated or broken: drop it. SecureChannel already closed it.
      socket.destroy();
    } finally {
      _pending--;
    }
  }
}
