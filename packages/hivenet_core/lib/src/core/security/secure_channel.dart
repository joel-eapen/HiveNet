import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import '../networking/length_prefixed_buffer.dart';
import '../networking/length_prefixed_framing.dart';
import '../networking/message_protocol.dart';
import 'device_identity.dart';
import 'ed25519_device_identity_service.dart';

/// What the local device knows about a peer that presented an identity.
enum PeerTrust {
  /// Paired, not revoked, and the key matches what was stored at pairing.
  trusted,

  /// Never seen. Only acceptable while pairing.
  unknown,

  /// Revoked, or presenting a different key than the one paired.
  rejected,
}

/// Decides how much to trust a peer that has proven it holds the key for the
/// node id it claims. Called after the signatures check out.
typedef PeerVerifier = FutureOr<PeerTrust> Function(
  String nodeId,
  Uint8List publicKey,
);

/// An authenticated, encrypted connection to one peer (PRD FR-01, FR-09).
///
/// Handshake (signed ephemeral Diffie-Hellman, in the style of STS):
///
/// ```text
/// C -> S  AUTH_HELLO   idPubC, ephC
/// S -> C  AUTH_REPLY   idPubS, ephS, Sign_S("S" || T)
/// C -> S  AUTH_FINISH  Sign_C("C" || T)
/// S -> C  AUTH_ACCEPT  (first encrypted message, sent only once S trusts C)
///
/// T = SHA-256(label || nodeIdC || nodeIdS || idPubC || idPubS || ephC || ephS)
/// ```
///
/// Each side checks that the other's node id really is derived from the public
/// key it presented, that the key is not a weak one, and that the signature
/// over the full transcript verifies. The transcript binds both identities and
/// both fresh ephemeral keys, so a signature cannot be replayed in another
/// session or reflected back (the "S" and "C" roles are signed too).
///
/// Session keys come from HKDF over the DH secret, salted with T, one key per
/// direction. Every later message is AES-256-GCM encrypted with a strictly
/// increasing counter as nonce. An attacker on the network can therefore not
/// read, alter, replay, drop or reorder messages without the receiver
/// noticing, and a bad frame ends the connection.
///
/// This relies on primitives from the `cryptography` package; only the
/// composition is custom. It deserves an independent review before release.
class SecureChannel {
  SecureChannel._({
    required this._socket,
    required this._queue,
    required this.peerNodeId,
    required this.peerPublicKey,
    required this.peerTrust,
    required this.channelBinding,
    required this._sendKey,
    required this._receiveKey,
    required int maxMessageBytes,
    required bool awaitAccept,
  })  : _framing = LengthPrefixedFraming(maxFrameBytes: maxMessageBytes),
        _maxMessageBytes = maxMessageBytes,
        _awaitingAccept = awaitAccept {
    // The server side has nothing to wait for. Marking the future handled
    // keeps an early failure from being reported as unhandled before the
    // handshake code gets around to awaiting it.
    _accepted.future.ignore();
    if (!awaitAccept) _accepted.complete();
    unawaited(_pump());
  }

  static const String _label = 'hivenet-auth-v1';
  static const String _kdfInfo = 'hivenet-session-v1';
  static final List<int> _frameAad = utf8.encode('hivenet-frame-v1');
  static const int _tagBytes = 16;
  static const int _defaultMaxMessage = 4 * 1024 * 1024;

  /// The peer's proven node id. Use this, never a `senderNodeId` in a message.
  final String peerNodeId;
  final Uint8List peerPublicKey;
  final PeerTrust peerTrust;

  /// A value both sides computed from the handshake and nobody else can
  /// reproduce. Pairing mixes it into its proof so the proof only works on
  /// this exact connection.
  final Uint8List channelBinding;

  final Socket _socket;
  final _FrameQueue _queue;
  final SecretKey _sendKey;
  final SecretKey _receiveKey;
  final LengthPrefixedFraming _framing;
  final int _maxMessageBytes;
  final AesGcm _aes = AesGcm.with256bits();
  final StreamController<MessageEnvelope> _incoming =
      StreamController<MessageEnvelope>();

  final Completer<void> _accepted = Completer<void>();
  bool _awaitingAccept;
  int _sendCounter = 0;
  int _receiveCounter = 0;
  Future<void> _sendTail = Future.value();
  bool _closed = false;

  /// Decrypted, authenticated messages. Ends when the connection closes; an
  /// error means the peer sent something invalid and the channel was closed.
  Stream<MessageEnvelope> get messages => _incoming.stream;

  // ------------------------------------------------------------- handshake

  /// Starts the handshake as the connecting side.
  ///
  /// If [expectedPeerKey] is given (for example from a pairing QR code), the
  /// handshake fails unless the server proves exactly that key.
  static Future<SecureChannel> connect(
    Socket socket, {
    required DeviceIdentity identity,
    required DeviceIdentityService signer,
    required PeerVerifier verifier,
    bool allowUnknown = false,
    Uint8List? expectedPeerKey,
    Duration timeout = const Duration(seconds: 10),
    int maxMessageBytes = _defaultMaxMessage,
  }) =>
      _run(
        socket,
        isClient: true,
        identity: identity,
        signer: signer,
        verifier: verifier,
        allowUnknown: allowUnknown,
        expectedPeerKey: expectedPeerKey,
        timeout: timeout,
        maxMessageBytes: maxMessageBytes,
      );

  /// Answers the handshake as the listening side.
  static Future<SecureChannel> accept(
    Socket socket, {
    required DeviceIdentity identity,
    required DeviceIdentityService signer,
    required PeerVerifier verifier,
    bool allowUnknown = false,
    Duration timeout = const Duration(seconds: 10),
    int maxMessageBytes = _defaultMaxMessage,
  }) =>
      _run(
        socket,
        isClient: false,
        identity: identity,
        signer: signer,
        verifier: verifier,
        allowUnknown: allowUnknown,
        expectedPeerKey: null,
        timeout: timeout,
        maxMessageBytes: maxMessageBytes,
      );

  static Future<SecureChannel> _run(
    Socket socket, {
    required bool isClient,
    required DeviceIdentity identity,
    required DeviceIdentityService signer,
    required PeerVerifier verifier,
    required bool allowUnknown,
    required Uint8List? expectedPeerKey,
    required Duration timeout,
    required int maxMessageBytes,
  }) async {
    // Large enough for any message plus the AEAD tag; small enough to bound
    // what an unauthenticated peer can make us buffer.
    final queue = _FrameQueue(socket, maxMessageBytes + _tagBytes + 64);
    try {
      final result = await (() async {
        final channel = await _handshake(
          socket, queue,
          isClient: isClient,
          identity: identity,
          signer: signer,
          verifier: verifier,
          allowUnknown: allowUnknown,
          expectedPeerKey: expectedPeerKey,
          maxMessageBytes: maxMessageBytes,
        );
        if (isClient) {
          // Not connected until the server says it accepts us. A server that
          // rejects us just closes, which fails this wait.
          await channel._accepted.future;
        } else {
          await channel.send(MessageEnvelope(
            type: MessageType.authAccept,
            requestId: 'handshake',
            senderNodeId: identity.nodeId,
          ));
        }
        return channel;
      })()
          .timeout(timeout, onTimeout: () {
        throw _denied('handshake timed out');
      });
      return result;
    } catch (e) {
      socket.destroy();
      await queue.dispose();
      if (e is HiveError) rethrow;
      throw _denied('handshake failed: ${e.runtimeType}');
    }
  }

  static Future<SecureChannel> _handshake(
    Socket socket,
    _FrameQueue queue, {
    required bool isClient,
    required DeviceIdentity identity,
    required DeviceIdentityService signer,
    required PeerVerifier verifier,
    required bool allowUnknown,
    required Uint8List? expectedPeerKey,
    required int maxMessageBytes,
  }) async {
    final x25519 = X25519();
    final ephemeral = await x25519.newKeyPair();
    final ephPublic =
        Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);

    _Hello peer;
    Uint8List transcript;
    Uint8List peerEph;

    if (isClient) {
      _send(socket, MessageType.authHello, identity.nodeId, {
        'pub': base64Encode(identity.publicKey),
        'eph': base64Encode(ephPublic),
      });
      final reply = await queue.nextEnvelope(MessageType.authReply);
      peer = _parsePeer(reply);
      peerEph = _bytes(reply.payload['eph'], 32, 'ephemeral key');
      transcript = _transcript(
        clientId: identity.nodeId,
        serverId: peer.nodeId,
        clientPub: identity.publicKey,
        serverPub: peer.publicKey,
        clientEph: ephPublic,
        serverEph: peerEph,
      );
      if (!await Ed25519DeviceIdentityService.verifySignature(
        message: _signed('S', transcript),
        signature: _bytes(reply.payload['sig'], 64, 'signature'),
        publicKey: peer.publicKey,
      )) {
        throw _denied('server signature is invalid');
      }
    } else {
      final hello = await queue.nextEnvelope(MessageType.authHello);
      peer = _parsePeer(hello);
      peerEph = _bytes(hello.payload['eph'], 32, 'ephemeral key');
      transcript = _transcript(
        clientId: peer.nodeId,
        serverId: identity.nodeId,
        clientPub: peer.publicKey,
        serverPub: identity.publicKey,
        clientEph: peerEph,
        serverEph: ephPublic,
      );
      final signature = await signer.sign(_signed('S', transcript));
      _send(socket, MessageType.authReply, identity.nodeId, {
        'pub': base64Encode(identity.publicKey),
        'eph': base64Encode(ephPublic),
        'sig': base64Encode(signature),
      });
    }

    // Who is this, and do we accept them? Decided before any key is used.
    if (expectedPeerKey != null && !_equal(expectedPeerKey, peer.publicKey)) {
      throw _denied('peer key does not match the expected key');
    }

    // The client confirms last, so the server only trusts it after the
    // client's signature verifies.
    if (isClient) {
      final signature = await signer.sign(_signed('C', transcript));
      _send(socket, MessageType.authFinish, identity.nodeId, {
        'sig': base64Encode(signature),
      });
    } else {
      final finish = await queue.nextEnvelope(MessageType.authFinish);
      if (!await Ed25519DeviceIdentityService.verifySignature(
        message: _signed('C', transcript),
        signature: _bytes(finish.payload['sig'], 64, 'signature'),
        publicKey: peer.publicKey,
      )) {
        throw _denied('client signature is invalid');
      }
    }

    final trust = await verifier(peer.nodeId, peer.publicKey);
    if (trust == PeerTrust.rejected) {
      throw _denied('peer is not trusted');
    }
    if (trust == PeerTrust.unknown && !allowUnknown) {
      throw _denied('peer is not paired');
    }

    // A low-order ephemeral key would make the shared secret predictable.
    final shared = await x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(peerEph, type: KeyPairType.x25519),
    );
    final sharedBytes = await shared.extractBytes();
    if (sharedBytes.every((b) => b == 0)) {
      throw _denied('weak ephemeral key');
    }

    final keyMaterial = await Hkdf(hmac: Hmac.sha256(), outputLength: 96).deriveKey(
      secretKey: shared,
      nonce: transcript,
      info: utf8.encode(_kdfInfo),
    );
    final km = await keyMaterial.extractBytes();
    final clientToServer = SecretKey(km.sublist(0, 32));
    final serverToClient = SecretKey(km.sublist(32, 64));

    return SecureChannel._(
      socket: socket,
      queue: queue,
      peerNodeId: peer.nodeId,
      peerPublicKey: peer.publicKey,
      peerTrust: trust,
      channelBinding: Uint8List.fromList(km.sublist(64, 96)),
      sendKey: isClient ? clientToServer : serverToClient,
      receiveKey: isClient ? serverToClient : clientToServer,
      maxMessageBytes: maxMessageBytes,
      awaitAccept: isClient,
    );
  }

  // --------------------------------------------------------------- session

  /// Encrypts and sends [message]. Calls are sent in the order made.
  Future<void> send(MessageEnvelope message) {
    final done = _sendTail.then((_) => _sendNow(message));
    _sendTail = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<void> _sendNow(MessageEnvelope message) async {
    if (_closed) throw _denied('channel is closed');
    final plain = _framing.encode(message);
    final counter = _sendCounter++;
    final box = await _aes.encrypt(
      plain,
      secretKey: _sendKey,
      nonce: _nonce(counter),
      aad: _frameAad,
    );
    _socket.add(LengthPrefixedBuffer.frame(
        Uint8List.fromList([...box.cipherText, ...box.mac.bytes])));
  }

  Future<void> _pump() async {
    try {
      while (!_closed) {
        final body = await _queue.next();
        if (body.length < _tagBytes) {
          throw _integrity('encrypted frame is too short');
        }
        final cipherEnd = body.length - _tagBytes;
        // The nonce is implied by our own counter, never read from the wire.
        // A replayed, dropped or reordered frame therefore fails to decrypt.
        List<int> plain;
        try {
          plain = await _aes.decrypt(
            SecretBox(
              body.sublist(0, cipherEnd),
              nonce: _nonce(_receiveCounter),
              mac: Mac(body.sublist(cipherEnd)),
            ),
            secretKey: _receiveKey,
            aad: _frameAad,
          );
        } on SecretBoxAuthenticationError {
          throw _integrity('frame failed authentication');
        }
        _receiveCounter++;
        if (plain.length > _maxMessageBytes + 8) {
          throw _integrity('message is too large');
        }
        final decoder = FrameDecoder(maxFrameBytes: _maxMessageBytes);
        final messages = decoder.add(plain);
        decoder.close();
        if (messages.length != 1) {
          throw _integrity('expected exactly one message per frame');
        }
        final message = messages.single;
        if (_awaitingAccept) {
          // The very first message must be the server's acceptance.
          if (message.type != MessageType.authAccept) {
            throw _denied('server did not accept the connection');
          }
          _awaitingAccept = false;
          _accepted.complete();
          continue;
        }
        if (message.type == MessageType.authAccept) {
          throw _integrity('unexpected acceptance message');
        }
        _incoming.add(message);
      }
    } on _PeerClosed {
      // Orderly end of the connection. If we were still waiting to be
      // accepted, the peer refused us.
      if (!_accepted.isCompleted) {
        _accepted.completeError(_denied('peer closed the connection: not accepted'));
      }
    } catch (e) {
      if (!_accepted.isCompleted) _accepted.completeError(e);
      if (!_closed) _incoming.addError(e);
    } finally {
      await close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    // Do not await the controller: with no listener its close() never
    // completes, which would make closing an unread channel hang forever.
    if (!_incoming.isClosed) unawaited(_incoming.close());
    await _queue.dispose();
  }

  // --------------------------------------------------------------- helpers

  static Uint8List _nonce(int counter) {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(4, counter);
    return nonce;
  }

  static Uint8List _signed(String role, Uint8List transcript) =>
      Uint8List.fromList([...utf8.encode(role), ...transcript]);

  static Uint8List _transcript({
    required String clientId,
    required String serverId,
    required Uint8List clientPub,
    required Uint8List serverPub,
    required Uint8List clientEph,
    required Uint8List serverEph,
  }) {
    // Every field is length-prefixed so two different field splits can never
    // produce the same bytes.
    final out = BytesBuilder();
    for (final part in [
      utf8.encode(_label),
      utf8.encode(clientId),
      utf8.encode(serverId),
      clientPub,
      serverPub,
      clientEph,
      serverEph,
    ]) {
      out.add((ByteData(4)..setUint32(0, part.length)).buffer.asUint8List());
      out.add(part);
    }
    return Uint8List.fromList(c.sha256.convert(out.toBytes()).bytes);
  }

  static void _send(
    Socket socket,
    MessageType type,
    String nodeId,
    Map<String, Object?> payload,
  ) {
    final env = MessageEnvelope(
      type: type,
      requestId: 'handshake',
      senderNodeId: nodeId,
      payload: payload,
    );
    socket.add(LengthPrefixedBuffer.frame(utf8.encode(jsonEncode(env.toJson()))));
  }

  static _Hello _parsePeer(MessageEnvelope env) {
    final publicKey = _bytes(env.payload['pub'], 32, 'public key');
    if (Ed25519DeviceIdentityService.isWeakPublicKey(publicKey)) {
      throw _denied('peer presented a weak key');
    }
    final claimed = env.senderNodeId;
    // The id is derived from the key, so claiming someone else's id needs
    // their private key.
    if (claimed != Ed25519DeviceIdentityService.nodeIdFor(publicKey)) {
      throw _denied('node id does not match the public key');
    }
    return _Hello(claimed, publicKey);
  }

  static Uint8List _bytes(Object? value, int length, String what) {
    if (value is! String) throw _denied('missing $what');
    final Uint8List decoded;
    try {
      decoded = base64Decode(value);
    } on FormatException {
      throw _denied('malformed $what');
    }
    if (decoded.length != length) throw _denied('$what has the wrong length');
    return decoded;
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static HiveError _denied(String detail) => HiveError(
        code: HiveErrorCode.unauthenticated,
        message: 'Could not establish a trusted connection.',
        technicalDetails: detail,
      );

  static HiveError _integrity(String detail) => HiveError(
        code: HiveErrorCode.integrityMismatch,
        message: 'A message failed verification and the connection was closed.',
        technicalDetails: detail,
      );
}

class _Hello {
  const _Hello(this.nodeId, this.publicKey);
  final String nodeId;
  final Uint8List publicKey;
}

class _PeerClosed implements Exception {
  const _PeerClosed();
}

/// Pulls length-prefixed frames off a socket one at a time.
class _FrameQueue {
  _FrameQueue(Stream<List<int>> source, int maxBody)
      : _buffer = LengthPrefixedBuffer(maxBodyBytes: maxBody) {
    _sub = source.listen(
      _onData,
      onError: _fail,
      onDone: () => _fail(const _PeerClosed()),
      cancelOnError: true,
    );
  }

  final LengthPrefixedBuffer _buffer;
  late final StreamSubscription<List<int>> _sub;
  final Queue<Uint8List> _frames = Queue();
  Completer<Uint8List>? _waiter;
  Object? _error;

  void _onData(List<int> data) {
    try {
      for (final body in _buffer.add(data)) {
        final waiter = _waiter;
        if (waiter != null) {
          _waiter = null;
          waiter.complete(body);
        } else {
          _frames.add(body);
        }
      }
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object error) {
    _error ??= error;
    final waiter = _waiter;
    if (waiter != null) {
      _waiter = null;
      waiter.completeError(error);
    }
  }

  Future<Uint8List> next() {
    if (_frames.isNotEmpty) return Future.value(_frames.removeFirst());
    if (_error != null) return Future.error(_error!);
    final completer = Completer<Uint8List>();
    _waiter = completer;
    return completer.future;
  }

  /// Reads one plain (handshake) envelope and checks its type.
  Future<MessageEnvelope> nextEnvelope(MessageType expected) async {
    final body = await next();
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) throw const FormatException('not an object');
      final env = MessageEnvelope.fromJson(Map<String, Object?>.from(decoded));
      if (env.type != expected) {
        throw FormatException('expected ${expected.wire}, got ${env.type.wire}');
      }
      return env;
    } on FormatException catch (e) {
      throw SecureChannel._denied('malformed handshake: ${e.message}');
    } catch (_) {
      throw SecureChannel._denied('malformed handshake message');
    }
  }

  Future<void> dispose() => _sub.cancel();
}
