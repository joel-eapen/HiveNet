import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';

import 'key_store.dart';

/// A device identity plus the service that signs for it.
class TestDevice {
  TestDevice(this.service, this.identity);
  final Ed25519DeviceIdentityService service;
  final DeviceIdentity identity;

  String get nodeId => identity.nodeId;
  Uint8List get publicKey => identity.publicKey;

  static Future<TestDevice> create([String name = 'device']) async {
    final service = Ed25519DeviceIdentityService(
      keyStore: MemoryKeyStore(),
      platform: DevicePlatform.android,
    );
    return TestDevice(service, await service.loadOrCreate(deviceName: name));
  }
}

/// Trusts exactly the devices it was told about, and rejects the rest or
/// reports them unknown.
PeerVerifier verifierFor(
  Iterable<TestDevice> trusted, {
  Set<String> revoked = const {},
  PeerTrust unlisted = PeerTrust.unknown,
}) {
  final keys = {for (final d in trusted) d.nodeId: d.publicKey};
  return (nodeId, publicKey) {
    if (revoked.contains(nodeId)) return PeerTrust.rejected;
    final known = keys[nodeId];
    if (known == null) return unlisted;
    if (known.length != publicKey.length) return PeerTrust.rejected;
    for (var i = 0; i < known.length; i++) {
      if (known[i] != publicKey[i]) return PeerTrust.rejected;
    }
    return PeerTrust.trusted;
  };
}

/// Two connected sockets over real loopback TCP.
class SocketPair {
  SocketPair(this.client, this.server, this._listener);
  final Socket client;
  final Socket server;
  final ServerSocket _listener;

  static Future<SocketPair> open() async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = listener.first;
    final client = await Socket.connect(InternetAddress.loopbackIPv4, listener.port);
    return SocketPair(client, await accepted, listener);
  }

  Future<void> close() async {
    client.destroy();
    server.destroy();
    await _listener.close();
  }
}

/// Runs both sides of a handshake at once.
Future<({SecureChannel client, SecureChannel server})> handshake(
  SocketPair pair, {
  required TestDevice client,
  required TestDevice server,
  PeerVerifier? clientVerifies,
  PeerVerifier? serverVerifies,
  bool clientAllowsUnknown = false,
  bool serverAllowsUnknown = false,
  Uint8List? expectedServerKey,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final s = SecureChannel.accept(
    pair.server,
    identity: server.identity,
    signer: server.service,
    verifier: serverVerifies ?? verifierFor([client]),
    allowUnknown: serverAllowsUnknown,
    timeout: timeout,
  );
  final c = SecureChannel.connect(
    pair.client,
    identity: client.identity,
    signer: client.service,
    verifier: clientVerifies ?? verifierFor([server]),
    allowUnknown: clientAllowsUnknown,
    expectedPeerKey: expectedServerKey,
    timeout: timeout,
  );
  // Surface a failure on either side without leaving the other as an
  // unhandled error.
  final results = await Future.wait([
    c.then<Object>((v) => v, onError: (Object e) => e),
    s.then<Object>((v) => v, onError: (Object e) => e),
  ]);
  for (final r in results) {
    if (r is! SecureChannel) throw r;
  }
  return (client: results[0] as SecureChannel, server: results[1] as SecureChannel);
}

/// A man in the middle between a client and a server. It forwards bytes in both
/// directions and can record, alter, or replay them.
class Mitm {
  Mitm._(this._listener, this.upstream);
  final ServerSocket _listener;
  final int upstream;

  /// Every byte seen, per direction.
  final BytesBuilder clientToServer = BytesBuilder();
  final BytesBuilder serverToClient = BytesBuilder();

  /// Return replacement bytes to alter traffic. Called per chunk.
  List<int> Function(List<int> data)? tamperClientToServer;
  List<int> Function(List<int> data)? tamperServerToClient;

  /// Set to make the proxy send each client->server chunk twice.
  bool duplicateClientToServer = false;

  int get port => _listener.port;

  static Future<Mitm> start(int upstreamPort) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final m = Mitm._(listener, upstreamPort);
    listener.listen((client) async {
      final server = await Socket.connect(InternetAddress.loopbackIPv4, upstreamPort);
      client.listen((d) {
        m.clientToServer.add(d);
        final out = m.tamperClientToServer?.call(d) ?? d;
        server.add(out);
        if (m.duplicateClientToServer) server.add(out);
      }, onDone: server.destroy, onError: (_) => server.destroy());
      server.listen((d) {
        m.serverToClient.add(d);
        client.add(m.tamperServerToClient?.call(d) ?? d);
      }, onDone: client.destroy, onError: (_) => client.destroy());
    });
    return m;
  }

  Future<void> close() async {
    await _listener.close();
  }
}

/// Opens a listener and connects through [Mitm]; returns the two real sockets
/// the endpoints will use.
Future<({Socket client, Socket server, Mitm mitm, ServerSocket listener})>
    connectThroughMitm() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = listener.first;
  final mitm = await Mitm.start(listener.port);
  final client = await Socket.connect(InternetAddress.loopbackIPv4, mitm.port);
  final server = await accepted;
  return (client: client, server: server, mitm: mitm, listener: listener);
}
