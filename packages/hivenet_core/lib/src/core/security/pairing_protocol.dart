import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import '../../shared/models/security_models.dart';
import '../networking/message_protocol.dart';
import 'device_identity.dart';
import 'ed25519_device_identity_service.dart';
import 'secure_channel.dart';

/// What the pairing QR code carries (PRD FR-01).
///
/// It holds the inviter's public identity plus a one-time secret. Scanning it
/// does two jobs: it pins the inviter's key, so the scanner cannot be tricked
/// into pairing with someone else, and it lets the scanner prove to the
/// inviter that it saw the code. The code also carries the address, so pairing
/// does not depend on mDNS.
class PairingInvite {
  PairingInvite({
    required this.nodeId,
    required this.publicKey,
    required this.host,
    required this.port,
    required this.secret,
    required this.expiresAt,
  });

  static const String scheme = 'hivenet://pair?d=';
  static const int version = 1;
  static const int secretBytes = 16;

  final String nodeId;
  final Uint8List publicKey;
  final String host;
  final int port;

  /// One-time secret. Never logged; treat the QR text like a password.
  final Uint8List secret;
  final DateTime expiresAt;

  String get fingerprint => Ed25519DeviceIdentityService.fingerprintFor(publicKey);

  String toQrString() => scheme +
      base64Url.encode(utf8.encode(jsonEncode({
        'v': version,
        'id': nodeId,
        'pk': base64Encode(publicKey),
        'h': host,
        'p': port,
        's': base64Encode(secret),
        'x': expiresAt.toUtc().millisecondsSinceEpoch,
      })));

  /// Parses and validates scanned text. Throws a [HiveError] for anything
  /// malformed, forged or expired.
  factory PairingInvite.parse(String text, {required DateTime now}) {
    try {
      if (!text.startsWith(scheme)) throw const FormatException('not a HiveNet code');
      final j = jsonDecode(utf8.decode(base64Url.decode(text.substring(scheme.length))));
      if (j is! Map || j['v'] != version) throw const FormatException('unsupported version');
      final key = base64Decode(j['pk'] as String);
      final id = j['id'] as String;
      final host = j['h'] as String;
      final port = j['p'] as int;
      final secret = base64Decode(j['s'] as String);
      final expires = DateTime.fromMillisecondsSinceEpoch(j['x'] as int, isUtc: true);

      if (key.length != 32 || Ed25519DeviceIdentityService.isWeakPublicKey(key)) {
        throw const FormatException('invalid device key');
      }
      if (id != Ed25519DeviceIdentityService.nodeIdFor(key)) {
        throw const FormatException('device id does not match its key');
      }
      if (host.isEmpty || port < 1 || port > 65535) {
        throw const FormatException('invalid address');
      }
      if (secret.length != secretBytes) throw const FormatException('invalid secret');
      if (!expires.isAfter(now)) throw const FormatException('this code has expired');
      return PairingInvite(
        nodeId: id,
        publicKey: key,
        host: host,
        port: port,
        secret: secret,
        expiresAt: expires,
      );
    } on HiveError {
      rethrow;
    } catch (e) {
      throw HiveError(
        code: HiveErrorCode.unauthenticated,
        message: 'This pairing code is not valid.',
        technicalDetails: e is FormatException ? e.message : e.runtimeType.toString(),
      );
    }
  }
}

/// Inviter-side state for one invite: valid once, for a short time, with a
/// small number of wrong attempts allowed.
class PairingInviteState {
  PairingInviteState({
    required this.invite,
    this.maxAttempts = 3,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PairingInvite invite;
  final int maxAttempts;
  final DateTime Function() _clock;
  int _attempts = 0;
  bool _used = false;

  bool get isUsable =>
      !_used && _attempts < maxAttempts && invite.expiresAt.isAfter(_clock());

  /// True exactly once, for the right proof on the connection it was made for.
  bool verifyAndConsume({
    required Uint8List proof,
    required Uint8List channelBinding,
    required String joinerNodeId,
  }) {
    if (!isUsable) return false;
    final expected = pairingProof(
      secret: invite.secret,
      channelBinding: channelBinding,
      joinerNodeId: joinerNodeId,
    );
    final ok = _constantTimeEqual(expected, proof);
    if (ok) {
      _used = true;
    } else {
      _attempts++;
    }
    return ok;
  }
}

/// HMAC over the secret, this connection's binding and the joiner's id. A proof
/// captured on one connection is useless on any other.
Uint8List pairingProof({
  required Uint8List secret,
  required Uint8List channelBinding,
  required String joinerNodeId,
}) {
  final mac = c.Hmac(c.sha256, secret);
  return Uint8List.fromList(mac.convert([
    ...utf8.encode('hivenet-pair-v1'),
    ...channelBinding,
    ...utf8.encode(joinerNodeId),
  ]).bytes);
}

bool _constantTimeEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Shown to each user so they can accept or refuse the other device.
typedef ConfirmPeer = FutureOr<bool> Function(String peerName, String fingerprint);

/// Stores a newly trusted device.
typedef SaveTrustedDevice = Future<void> Function(TrustedDevice device);

HiveError _refused(String detail) => HiveError(
      code: HiveErrorCode.accessDenied,
      message: 'Pairing was not completed.',
      technicalDetails: detail,
    );

TrustedDevice _trusted(String name, Uint8List key, DateTime now) => TrustedDevice(
      nodeId: Ed25519DeviceIdentityService.nodeIdFor(key),
      publicKey: base64Encode(key),
      fingerprint: Ed25519DeviceIdentityService.fingerprintFor(key),
      displayName: name,
      pairedAt: now.toUtc(),
      trustStatus: TrustStatus.paired,
    );

String _name(Object? v) {
  final s = v is String ? v.trim() : '';
  // Display names come from the peer: keep them short and printable.
  return s.isEmpty ? 'Unnamed device' : (s.length > 40 ? s.substring(0, 40) : s);
}

MessageEnvelope _pairMsg(MessageType type, String nodeId, Map<String, Object?> payload) =>
    MessageEnvelope(type: type, requestId: 'pair', senderNodeId: nodeId, payload: payload);

/// The device that scanned the code. Runs over a channel opened with
/// `SecureChannel.connect(..., expectedPeerKey: invite.publicKey,
/// allowUnknown: true)`.
///
/// Returns the inviter as a trusted device once BOTH users accepted. The
/// device is saved only then.
Future<TrustedDevice> runPairingAsJoiner({
  required SecureChannel channel,
  required PairingInvite invite,
  required DeviceIdentity self,
  required ConfirmPeer confirm,
  required SaveTrustedDevice save,
  int? listenPort,
  Duration timeout = const Duration(minutes: 2),
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final inbox = StreamIterator(channel.messages);
  try {
    if (!_equalBytes(channel.peerPublicKey, invite.publicKey)) {
      throw _refused('connected device is not the one in the code');
    }
    await channel.send(_pairMsg(MessageType.pairRequest, self.nodeId, {
      'name': self.deviceName,
      // Where this device listens, so the inviter can reach it later without
      // relying on mDNS.
      if (listenPort != null) 'port': listenPort,
      'proof': base64Encode(pairingProof(
        secret: invite.secret,
        channelBinding: channel.channelBinding,
        joinerNodeId: self.nodeId,
      )),
    }));

    final theirs = await _next(inbox, MessageType.pairConfirm, timeout);
    if (theirs.payload['accepted'] != true) {
      throw _refused('the other device declined');
    }
    final inviterName = _name(theirs.payload['name']);

    final mine = await confirm(inviterName, invite.fingerprint);
    await channel.send(_pairMsg(MessageType.pairConfirm, self.nodeId, {'accepted': mine}));
    if (!mine) throw _refused('declined on this device');

    final done = await _next(inbox, MessageType.pairConfirm, timeout);
    if (done.payload['done'] != true) throw _refused('the other device did not finish');

    final device = _trusted(inviterName, invite.publicKey, now());
    await save(device);
    return device;
  } finally {
    await inbox.cancel();
    await channel.close();
  }
}

/// The device that showed the code. Runs over a channel opened with
/// `SecureChannel.accept(..., allowUnknown: true)`.
Future<TrustedDevice> runPairingAsInviter({
  required SecureChannel channel,
  required PairingInviteState state,
  required DeviceIdentity self,
  required ConfirmPeer confirm,
  required SaveTrustedDevice save,
  void Function(int port)? onPeerPort,
  Duration timeout = const Duration(minutes: 2),
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final inbox = StreamIterator(channel.messages);
  try {
    final request = await _next(inbox, MessageType.pairRequest, timeout);
    final proof = _decode(request.payload['proof']);
    final valid = state.verifyAndConsume(
      proof: proof,
      channelBinding: channel.channelBinding,
      joinerNodeId: channel.peerNodeId,
    );
    if (!valid) {
      await channel.send(_pairMsg(MessageType.pairConfirm, self.nodeId, {'accepted': false}));
      throw _refused('invalid, used or expired pairing code');
    }
    final joinerName = _name(request.payload['name']);
    final port = request.payload['port'];
    if (port is int && port > 0 && port < 65536) onPeerPort?.call(port);
    final joinerFingerprint =
        Ed25519DeviceIdentityService.fingerprintFor(channel.peerPublicKey);

    final mine = await confirm(joinerName, joinerFingerprint);
    await channel.send(_pairMsg(MessageType.pairConfirm, self.nodeId, {
      'accepted': mine,
      'name': self.deviceName,
    }));
    if (!mine) throw _refused('declined on this device');

    final theirs = await _next(inbox, MessageType.pairConfirm, timeout);
    final accepted = theirs.payload['accepted'] == true;
    if (accepted) {
      await save(_trusted(joinerName, channel.peerPublicKey, now()));
    }
    await channel.send(_pairMsg(MessageType.pairConfirm, self.nodeId, {'done': accepted}));
    if (!accepted) throw _refused('the other device declined');
    return _trusted(joinerName, channel.peerPublicKey, now());
  } finally {
    await inbox.cancel();
    await channel.close();
  }
}

Future<MessageEnvelope> _next(
  StreamIterator<MessageEnvelope> inbox,
  MessageType expected,
  Duration timeout,
) async {
  final has = await inbox.moveNext().timeout(timeout, onTimeout: () {
    throw _refused('timed out waiting for the other device');
  });
  if (!has) throw _refused('the other device disconnected');
  final m = inbox.current;
  if (m.type != expected) throw _refused('unexpected ${m.type.wire}');
  return m;
}

Uint8List _decode(Object? v) {
  try {
    return base64Decode(v as String);
  } catch (_) {
    return Uint8List(0);
  }
}

bool _equalBytes(Uint8List a, Uint8List b) => _constantTimeEqual(a, b);

/// Builds the connection-time check from stored devices: trusted only if the
/// device is paired, not revoked, and presents the key it paired with.
PeerVerifier trustedDeviceVerifier(
  FutureOr<TrustedDevice?> Function(String nodeId) lookup,
) {
  return (nodeId, publicKey) async {
    final device = await lookup(nodeId);
    if (device == null) return PeerTrust.unknown;
    if (device.trustStatus != TrustStatus.paired || device.revokedAt != null) {
      return PeerTrust.rejected;
    }
    return base64Encode(publicKey) == device.publicKey
        ? PeerTrust.trusted
        : PeerTrust.rejected;
  };
}
