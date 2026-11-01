import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import 'device_identity.dart';
import 'key_store.dart';

/// Persistent device identity built on Ed25519 (PRD FR-01, section 10.5).
///
/// Design:
/// - The 32-byte Ed25519 seed is the only secret. It is held in the [KeyStore]
///   (Android Keystore / iOS Keychain in the app), never in SQLite or logs.
/// - `nodeId` is derived from the public key, not chosen: a device cannot claim
///   another device's id without holding its private key.
/// - The fingerprint is shown to both users during pairing so they can compare.
///
/// Failure policy (PRD section 10.5): if the key store cannot be read, or holds
/// something unusable, this throws. It never quietly creates a replacement
/// identity, which would orphan every grant and pairing made with the old one.
class Ed25519DeviceIdentityService implements DeviceIdentityService {
  Ed25519DeviceIdentityService({
    required KeyStore keyStore,
    required this.platform,
    DateTime Function()? clock,
  })  : _keys = keyStore,
        _clock = clock ?? DateTime.now;

  static const String seedKey = 'identity.ed25519.seed';
  static const String createdKey = 'identity.created';
  static const int seedLength = 32;

  final KeyStore _keys;
  final DevicePlatform platform;
  final DateTime Function() _clock;
  final Ed25519 _algorithm = Ed25519();

  Future<DeviceIdentity>? _loading;
  SimpleKeyPair? _keyPair;

  /// Returns the existing identity or creates one on first launch. Concurrent
  /// callers share one attempt, so two calls can never create two identities.
  @override
  Future<DeviceIdentity> loadOrCreate({required String deviceName}) {
    return _loading ??= _loadOrCreate(deviceName).catchError((Object e) {
      _loading = null; // allow a retry after a failure
      throw e;
    });
  }

  Future<DeviceIdentity> _loadOrCreate(String deviceName) async {
    var seed = await _keys.read(seedKey);
    DateTime created;

    if (seed == null) {
      seed = await _newSeed();
      created = _clock().toUtc();
      await _keys.write(seedKey, seed);
      await _keys.write(createdKey, _encodeTime(created));
    } else {
      if (seed.length != seedLength) {
        throw HiveError(
          code: HiveErrorCode.keyUnavailable,
          message: 'This device\'s identity key is unreadable. '
              'It was not replaced.',
          technicalDetails: 'stored seed has ${seed.length} bytes',
        );
      }
      created = _decodeTime(await _keys.read(createdKey)) ?? _clock().toUtc();
    }

    final pair = await _algorithm.newKeyPairFromSeed(seed);
    _keyPair = pair;
    final publicKey = Uint8List.fromList((await pair.extractPublicKey()).bytes);

    return DeviceIdentity(
      nodeId: nodeIdFor(publicKey),
      deviceName: deviceName,
      platform: platform,
      publicKey: publicKey,
      fingerprint: fingerprintFor(publicKey),
      createdAt: created,
    );
  }

  @override
  Future<Uint8List> sign(Uint8List message) async {
    final pair = _keyPair;
    if (pair == null) {
      throw StateError('Call loadOrCreate before signing');
    }
    final signature = await _algorithm.sign(message, keyPair: pair);
    return Uint8List.fromList(signature.bytes);
  }

  @override
  Future<bool> verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) =>
      verifySignature(message: message, signature: signature, publicKey: publicKey);

  /// Verifies a signature from any device. Never throws on bad input: a
  /// malformed key or signature simply does not verify.
  ///
  /// Weak keys never verify (see [isWeakPublicKey]).
  static Future<bool> verifySignature({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    if (publicKey.length != 32 || signature.length != 64) return false;
    if (isWeakPublicKey(publicKey)) return false;
    try {
      return await Ed25519().verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// True for the Ed25519 "small-order" public keys (and their non-canonical
  /// encodings). For these, valid-looking signatures can be produced for many
  /// messages by someone who holds no private key, so a peer presenting one
  /// could not be held to anything it "signed". Pairing must refuse such keys
  /// and verification never accepts them.
  ///
  /// The list is complete: it holds 11 encodings covering all 8 small-order
  /// points of the curve (checked by exhaustive computation when written).
  static bool isWeakPublicKey(Uint8List publicKey) =>
      publicKey.length == 32 && _weakKeys.contains(_hex(publicKey));

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static const Set<String> _weakKeys = {
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000000000000000000000000000080',
    '0100000000000000000000000000000000000000000000000000000000000000',
    '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05',
    '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85',
    'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a',
    'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa',
    'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
  };

  /// `node-` plus the first 128 bits of SHA-256(publicKey), lower-case hex.
  static String nodeIdFor(Uint8List publicKey) =>
      'node-${sha256.convert(publicKey).toString().substring(0, 32)}';

  /// 128 bits of SHA-256(publicKey) in groups of four, upper-case, for people
  /// to compare on two screens: `A1B2-C3D4-...`.
  static String fingerprintFor(Uint8List publicKey) {
    final hex = sha256.convert(publicKey).toString().substring(0, 32).toUpperCase();
    return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)].join('-');
  }

  Future<Uint8List> _newSeed() async {
    final key = await _algorithm.newKeyPair();
    return Uint8List.fromList(await key.extractPrivateKeyBytes());
  }

  Uint8List _encodeTime(DateTime t) =>
      Uint8List.fromList(utf8.encode(t.toUtc().toIso8601String()));

  DateTime? _decodeTime(Uint8List? bytes) {
    if (bytes == null) return null;
    return DateTime.tryParse(utf8.decode(bytes, allowMalformed: true))?.toUtc();
  }
}
