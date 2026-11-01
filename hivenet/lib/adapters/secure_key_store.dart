import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hivenet_core/hivenet_core.dart';

/// [KeyStore] backed by Android Keystore / iOS Keychain (PRD section 10.5).
///
/// Errors propagate. Callers must not respond to a read failure by creating a
/// replacement identity.
class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> read(String name) async {
    final value = await _storage.read(key: name);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> write(String name, Uint8List value) =>
      _storage.write(key: name, value: base64Encode(value));

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}
