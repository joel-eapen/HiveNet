import 'dart:typed_data';

class EncryptedObject {
  const EncryptedObject({
    required this.ciphertext,
    required this.ciphertextHash,
    required this.imageKey,
  });

  /// AES-256-GCM output (PRD FR-09). Replicated as-is, never re-encrypted per
  /// destination.
  final Uint8List ciphertext;

  /// SHA-256 of [ciphertext], hex.
  final String ciphertextHash;

  /// Per-image data-encryption key. Hold in memory only until wrapped for the
  /// owner and authorized recipients; never persist or log it.
  final Uint8List imageKey;
}

/// Per-image encryption and key wrapping (PRD FR-09, FR-09A). Use vetted
/// primitives from the `cryptography` package; do not hand-roll crypto.
///
/// A storage peer never receives a plaintext key. Keys are wrapped for each
/// authorized recipient device's public key.
abstract interface class EncryptionService {
  Future<EncryptedObject> encrypt(Uint8List plaintext);

  /// Decrypts and authenticates. Throws on tampering.
  Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required Uint8List imageKey,
  });

  Future<Uint8List> wrapKey({
    required Uint8List imageKey,
    required Uint8List recipientPublicKey,
  });

  Future<Uint8List> unwrapKey(Uint8List wrappedKey);
}

class UnimplementedEncryptionService implements EncryptionService {
  const UnimplementedEncryptionService();

  @override
  Future<EncryptedObject> encrypt(Uint8List plaintext) =>
      throw UnimplementedError('EncryptionService: Milestone 3');

  @override
  Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required Uint8List imageKey,
  }) =>
      throw UnimplementedError('EncryptionService: Milestone 3');

  @override
  Future<Uint8List> wrapKey({
    required Uint8List imageKey,
    required Uint8List recipientPublicKey,
  }) =>
      throw UnimplementedError('EncryptionService: Milestone 6');

  @override
  Future<Uint8List> unwrapKey(Uint8List wrappedKey) =>
      throw UnimplementedError('EncryptionService: Milestone 6');
}
