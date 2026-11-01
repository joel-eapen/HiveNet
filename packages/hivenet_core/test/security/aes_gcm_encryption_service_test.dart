import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  final service = AesGcmEncryptionService();

  Uint8List bytesOf(int n) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 11 + 7) % 256));

  Future<EncryptedObject> enc([Uint8List? data]) =>
      service.encrypt(data ?? bytesOf(2000));

  HiveErrorCode? codeOf(Object e) => e is HiveError ? e.code : null;

  test('round trips', () async {
    final data = bytesOf(100000);
    final obj = await service.encrypt(data);
    expect(await service.decrypt(ciphertext: obj.ciphertext, imageKey: obj.imageKey),
        data);
  });

  test('round trips empty and tiny inputs', () async {
    for (final n in [0, 1, 15, 16, 17]) {
      final data = bytesOf(n);
      final obj = await service.encrypt(data);
      expect(
          await service.decrypt(ciphertext: obj.ciphertext, imageKey: obj.imageKey),
          data,
          reason: 'length $n');
    }
  });

  test('has the documented format and a 256-bit key', () async {
    final data = bytesOf(1000);
    final obj = await service.encrypt(data);
    expect(obj.imageKey.length, 32);
    expect(obj.ciphertext[0], 1, reason: 'version byte');
    expect(obj.ciphertext.length, 1 + 12 + data.length + 16);
  });

  test('ciphertext does not contain the plaintext', () async {
    final data = Uint8List.fromList(List.filled(4096, 0x41));
    final obj = await service.encrypt(data);
    final body = obj.ciphertext.sublist(13, obj.ciphertext.length - 16);
    expect(body, isNot(data));
    expect(body.toSet().length, greaterThan(100));
  });

  test('ciphertextHash is the SHA-256 of the whole object', () async {
    final obj = await enc();
    expect(obj.ciphertextHash, crypto.sha256.convert(obj.ciphertext).toString());
    expect(obj.ciphertextHash, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('every call uses a fresh key and nonce', () async {
    final data = bytesOf(500);
    final a = await service.encrypt(data);
    final b = await service.encrypt(data);
    expect(a.imageKey, isNot(b.imageKey));
    expect(a.ciphertext.sublist(1, 13), isNot(b.ciphertext.sublist(1, 13)));
    expect(a.ciphertext, isNot(b.ciphertext));
    expect(a.ciphertextHash, isNot(b.ciphertextHash));
  });

  group('tampering is always detected', () {
    Future<void> expectRejected(Uint8List bad, Uint8List key) async {
      await expectLater(
        service.decrypt(ciphertext: bad, imageKey: key),
        throwsA(isA<HiveError>()
            .having((e) => e.code, 'code', HiveErrorCode.integrityMismatch)),
      );
    }

    test('a flipped bit in the ciphertext body', () async {
      final obj = await enc();
      final bad = Uint8List.fromList(obj.ciphertext)..[100] ^= 0x01;
      await expectRejected(bad, obj.imageKey);
    });

    test('a flipped bit in the tag', () async {
      final obj = await enc();
      final bad = Uint8List.fromList(obj.ciphertext)
        ..[obj.ciphertext.length - 1] ^= 0x80;
      await expectRejected(bad, obj.imageKey);
    });

    test('a flipped bit in the nonce', () async {
      final obj = await enc();
      final bad = Uint8List.fromList(obj.ciphertext)..[5] ^= 0x01;
      await expectRejected(bad, obj.imageKey);
    });

    test('a changed version byte', () async {
      final obj = await enc();
      final bad = Uint8List.fromList(obj.ciphertext)..[0] = 2;
      await expectRejected(bad, obj.imageKey);
    });

    test('a truncated object', () async {
      final obj = await enc();
      await expectRejected(
          Uint8List.fromList(obj.ciphertext.sublist(0, obj.ciphertext.length - 1)),
          obj.imageKey);
    });

    test('an object too short to hold a nonce and tag', () async {
      final obj = await enc();
      await expectRejected(Uint8List(10), obj.imageKey);
      await expectRejected(Uint8List(0), obj.imageKey);
    });

    test('appended bytes', () async {
      final obj = await enc();
      await expectRejected(
          Uint8List.fromList([...obj.ciphertext, 0]), obj.imageKey);
    });

    test('the wrong key', () async {
      final a = await enc();
      final b = await enc();
      await expectRejected(a.ciphertext, b.imageKey);
    });
  });

  test('a key of the wrong length is a programming error', () async {
    final obj = await enc();
    expect(service.decrypt(ciphertext: obj.ciphertext, imageKey: Uint8List(16)),
        throwsArgumentError);
  });

  test('error messages never include key or plaintext bytes', () async {
    final obj = await enc();
    try {
      await service.decrypt(
          ciphertext: Uint8List.fromList(obj.ciphertext)..[50] ^= 1,
          imageKey: obj.imageKey);
      fail('should have thrown');
    } on HiveError catch (e) {
      final text = '${e.message} ${e.technicalDetails}';
      expect(text, isNot(contains(obj.imageKey.join(','))));
      expect(codeOf(e), HiveErrorCode.integrityMismatch);
    }
  });

  test('key wrapping is deliberately not implemented yet', () {
    expect(() => service.wrapKey(imageKey: Uint8List(32), recipientPublicKey: Uint8List(32)),
        throwsUnimplementedError);
    expect(() => service.unwrapKey(Uint8List(1)), throwsUnimplementedError);
  });

  test('a 2 MB image encrypts and decrypts in reasonable time', () async {
    final data = bytesOf(2 * 1024 * 1024);
    final sw = Stopwatch()..start();
    final obj = await service.encrypt(data);
    final back =
        await service.decrypt(ciphertext: obj.ciphertext, imageKey: obj.imageKey);
    sw.stop();
    expect(back, data);
    // Generous bound: this only guards against pathological slowness.
    expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
    // ignore: avoid_print
    print('2 MiB encrypt+decrypt (pure Dart, VM): ${sw.elapsedMilliseconds} ms');
  });
}
