import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import 'encryption_service.dart';

/// Per-image AES-256-GCM encryption (PRD FR-09), built on the `cryptography`
/// package. No primitive is implemented here.
///
/// Object format:
///
/// ```text
/// [u8 version = 1][12-byte nonce][ciphertext][16-byte GCM tag]
/// ```
///
/// The version byte is also bound in as associated data, so changing it
/// invalidates the tag.
///
/// Performance: the pure-Dart cipher is slow on large inputs. Run [encrypt]
/// and [decrypt] in a background isolate from the app so the UI thread is not
/// blocked (PRD FR-03).
///
/// Key wrapping for recipient devices needs device identity and arrives with
/// Milestone 6.
class AesGcmEncryptionService implements EncryptionService {
  AesGcmEncryptionService() : _cipher = AesGcm.with256bits();

  static const int formatVersion = 1;
  static const int keyBytes = 32;
  static const int nonceBytes = 12;
  static const int tagBytes = 16;

  final AesGcm _cipher;

  static final List<int> _aad = [formatVersion];

  @override
  Future<EncryptedObject> encrypt(Uint8List plaintext) async {
    final key = await _cipher.newSecretKey();
    final nonce = _cipher.newNonce(); // random 96-bit nonce, fresh per object
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: _aad,
    );

    final body = box.concatenation(); // nonce + ciphertext + tag
    final out = Uint8List(1 + body.length)
      ..[0] = formatVersion
      ..setRange(1, 1 + body.length, body);

    return EncryptedObject(
      ciphertext: out,
      ciphertextHash: sha256.convert(out).toString(),
      imageKey: Uint8List.fromList(await key.extractBytes()),
    );
  }

  @override
  Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required Uint8List imageKey,
  }) async {
    if (imageKey.length != keyBytes) {
      throw ArgumentError.value(
        imageKey.length,
        'imageKey',
        'must be $keyBytes bytes',
      );
    }
    if (ciphertext.length < 1 + nonceBytes + tagBytes) {
      throw _integrityError('encrypted object is too short');
    }
    if (ciphertext[0] != formatVersion) {
      throw _integrityError('unsupported object version ${ciphertext[0]}');
    }

    try {
      final box = SecretBox.fromConcatenation(
        ciphertext.sublist(1),
        nonceLength: nonceBytes,
        macLength: tagBytes,
      );
      final clear = await _cipher.decrypt(
        box,
        secretKey: SecretKey(imageKey),
        aad: _aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      // Wrong key or tampered data: the two are indistinguishable by design.
      throw _integrityError('authentication failed');
    }
  }

  @override
  Future<Uint8List> wrapKey({
    required Uint8List imageKey,
    required Uint8List recipientPublicKey,
  }) =>
      throw UnimplementedError('Key wrapping: Milestone 6');

  @override
  Future<Uint8List> unwrapKey(Uint8List wrappedKey) =>
      throw UnimplementedError('Key unwrapping: Milestone 6');

  HiveError _integrityError(String detail) => HiveError(
        code: HiveErrorCode.integrityMismatch,
        message: 'The image failed verification and was not opened.',
        technicalDetails: detail,
      );
}
