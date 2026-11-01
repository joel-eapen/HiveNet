import 'dart:typed_data';

/// Platform-backed secret storage (Android Keystore / iOS Keychain), PRD
/// §10.5. Private keys and key-encryption material live only here: never in
/// SQLite, preferences, logs or ordinary files.
///
/// Implementations must fail loudly on access errors. Silently generating a
/// replacement identity would orphan existing grants.
abstract interface class KeyStore {
  Future<Uint8List?> read(String name);
  Future<void> write(String name, Uint8List value);
  Future<void> delete(String name);
}
