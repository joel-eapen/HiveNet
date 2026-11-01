import 'dart:io';

import 'package:crypto/crypto.dart';

import 'integrity_checker.dart';

/// SHA-256 integrity checks using the `crypto` package.
///
/// Files are hashed as a stream, so a large object is never held in memory.
/// Digests are lowercase hex.
class Sha256IntegrityChecker implements IntegrityChecker {
  const Sha256IntegrityChecker();

  @override
  Future<String> sha256OfFile(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  @override
  Future<String> sha256OfBytes(List<int> bytes) async =>
      sha256.convert(bytes).toString();

  @override
  Future<bool> verifyFile(String path, String expectedSha256) async {
    final actual = await sha256OfFile(path);
    return actual == expectedSha256.toLowerCase();
  }
}
