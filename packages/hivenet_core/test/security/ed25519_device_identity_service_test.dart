import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

class MemoryKeyStore implements KeyStore {
  final Map<String, Uint8List> data = {};
  int writes = 0;
  Object? failReads;
  Object? failWrites;

  @override
  Future<Uint8List?> read(String name) async {
    if (failReads != null) throw failReads!;
    return data[name];
  }

  @override
  Future<void> write(String name, Uint8List value) async {
    if (failWrites != null) throw failWrites!;
    writes++;
    data[name] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String name) async => data.remove(name);
}

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  late MemoryKeyStore store;
  Ed25519DeviceIdentityService service([DateTime Function()? clock]) =>
      Ed25519DeviceIdentityService(
          keyStore: store, platform: DevicePlatform.android, clock: clock);

  setUp(() => store = MemoryKeyStore());

  group('creating and restoring', () {
    test('first launch creates an identity and stores only the seed and time', () async {
      final id = await service().loadOrCreate(deviceName: 'Joel phone');
      expect(id.deviceName, 'Joel phone');
      expect(id.platform, DevicePlatform.android);
      expect(id.publicKey.length, 32);
      expect(store.data.keys.toSet(),
          {Ed25519DeviceIdentityService.seedKey, Ed25519DeviceIdentityService.createdKey});
      expect(store.data[Ed25519DeviceIdentityService.seedKey]!.length, 32);
    });

    test('the same identity comes back after a restart', () async {
      final first = await service().loadOrCreate(deviceName: 'a');
      final again = await service().loadOrCreate(deviceName: 'a'); // new instance
      expect(again.nodeId, first.nodeId);
      expect(again.publicKey, first.publicKey);
      expect(again.fingerprint, first.fingerprint);
      expect(again.createdAt, first.createdAt);
    });

    test('a restart does not write anything', () async {
      await service().loadOrCreate(deviceName: 'a');
      final writes = store.writes;
      await service().loadOrCreate(deviceName: 'a');
      expect(store.writes, writes);
    });

    test('two devices get different identities', () async {
      final a = await service().loadOrCreate(deviceName: 'a');
      store = MemoryKeyStore();
      final b = await service().loadOrCreate(deviceName: 'b');
      expect(a.nodeId, isNot(b.nodeId));
      expect(a.publicKey, isNot(b.publicKey));
    });

    test('concurrent first calls create exactly one identity', () async {
      final s = service();
      final ids = await Future.wait([
        for (var i = 0; i < 10; i++) s.loadOrCreate(deviceName: 'a'),
      ]);
      expect({for (final i in ids) i.nodeId}, hasLength(1));
      expect(store.writes, 2, reason: 'one seed and one timestamp, written once');
    });

    test('the creation time is the first launch, not the latest', () async {
      final t1 = DateTime.utc(2026, 11, 1, 9);
      final first = await service(() => t1).loadOrCreate(deviceName: 'a');
      final later = await service(() => DateTime.utc(2027)).loadOrCreate(deviceName: 'a');
      expect(first.createdAt, t1);
      expect(later.createdAt, t1);
    });

    test('a lost timestamp does not lose the identity', () async {
      final first = await service().loadOrCreate(deviceName: 'a');
      store.data.remove(Ed25519DeviceIdentityService.createdKey);
      final again = await service().loadOrCreate(deviceName: 'a');
      expect(again.nodeId, first.nodeId);
    });
  });

  group('identifiers', () {
    test('the node id is derived from the public key', () async {
      final id = await service().loadOrCreate(deviceName: 'a');
      expect(id.nodeId, Ed25519DeviceIdentityService.nodeIdFor(id.publicKey));
      expect(id.nodeId, matches(RegExp(r'^node-[0-9a-f]{32}$')));
    });

    test('the fingerprint is readable groups of four', () async {
      final id = await service().loadOrCreate(deviceName: 'a');
      expect(id.fingerprint, matches(RegExp(r'^([0-9A-F]{4}-){7}[0-9A-F]{4}$')));
    });

    test('a different key can never produce the same node id', () {
      final a = Uint8List(32)..[0] = 1;
      final b = Uint8List(32)..[0] = 2;
      expect(Ed25519DeviceIdentityService.nodeIdFor(a),
          isNot(Ed25519DeviceIdentityService.nodeIdFor(b)));
    });
  });

  group('signing', () {
    late Ed25519DeviceIdentityService s;
    late DeviceIdentity id;
    setUp(() async {
      s = service();
      id = await s.loadOrCreate(deviceName: 'a');
    });

    test('a signature verifies with the matching public key', () async {
      final msg = bytes('grant: view image abc for node-x');
      final sig = await s.sign(msg);
      expect(sig.length, 64);
      expect(await s.verify(message: msg, signature: sig, publicKey: id.publicKey), isTrue);
    });

    test('verification works across a restart', () async {
      final msg = bytes('hello');
      final sig = await s.sign(msg);
      final restarted = service();
      final again = await restarted.loadOrCreate(deviceName: 'a');
      expect(await restarted.verify(message: msg, signature: sig, publicKey: again.publicKey), isTrue);
      expect(await restarted.sign(msg), sig, reason: 'Ed25519 is deterministic');
    });

    test('a changed message does not verify', () async {
      final sig = await s.sign(bytes('amount=10'));
      expect(await s.verify(message: bytes('amount=99'), signature: sig, publicKey: id.publicKey), isFalse);
    });

    test('a changed signature does not verify', () async {
      final msg = bytes('x');
      final sig = Uint8List.fromList(await s.sign(msg))..[5] ^= 1;
      expect(await s.verify(message: msg, signature: sig, publicKey: id.publicKey), isFalse);
    });

    test("another device's key does not verify it", () async {
      final other = Ed25519DeviceIdentityService(
          keyStore: MemoryKeyStore(), platform: DevicePlatform.ios);
      final otherId = await other.loadOrCreate(deviceName: 'b');
      final msg = bytes('x');
      final sig = await s.sign(msg);
      expect(await s.verify(message: msg, signature: sig, publicKey: otherId.publicKey), isFalse);
    });

    test('malformed keys and signatures are rejected, never thrown', () async {
      final msg = bytes('x');
      final sig = await s.sign(msg);
      expect(await s.verify(message: msg, signature: Uint8List(10), publicKey: id.publicKey), isFalse);
      expect(await s.verify(message: msg, signature: sig, publicKey: Uint8List(5)), isFalse);
      expect(await s.verify(message: msg, signature: Uint8List(64), publicKey: Uint8List(32)), isFalse);
    });

    test('weak (small-order) public keys never verify, even with a forged-looking signature', () async {
      // An all-zero key with an all-zero signature is the textbook case: with
      // naive verification it "signs" many messages without any private key.
      final weakKeys = <Uint8List>[
        Uint8List(32),
        Uint8List.fromList([1, ...List.filled(31, 0)]),
        Uint8List.fromList([...List.filled(31, 0), 0x80]),
      ];
      for (final key in weakKeys) {
        expect(Ed25519DeviceIdentityService.isWeakPublicKey(key), isTrue);
        for (final msg in [bytes('a'), bytes('grant everything'), Uint8List(0)]) {
          expect(await s.verify(message: msg, signature: Uint8List(64), publicKey: key), isFalse);
          final identity = Uint8List.fromList([1, ...List.filled(31, 0), ...List.filled(32, 0)]);
          expect(await s.verify(message: msg, signature: identity, publicKey: key), isFalse);
        }
      }
    });

    test('the weak-key list has the 11 encodings of all 8 small-order points', () {
      final listed = <String>[
        '00' * 32,
        '${'00' * 31}80',
        '01${'00' * 31}',
        '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05',
        '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85',
        'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a',
        'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa',
        'ec${'ff' * 30}7f',
        'ed${'ff' * 30}7f',
        'ed${'ff' * 31}',
        'ee${'ff' * 30}7f',
      ];
      for (final hex in listed) {
        final key = Uint8List.fromList([
          for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
        ]);
        expect(Ed25519DeviceIdentityService.isWeakPublicKey(key), isTrue, reason: hex);
      }
    });

    test('real keys are never flagged as weak', () async {
      expect(Ed25519DeviceIdentityService.isWeakPublicKey(id.publicKey), isFalse);
      for (var i = 0; i < 20; i++) {
        final other = Ed25519DeviceIdentityService(
            keyStore: MemoryKeyStore(), platform: DevicePlatform.ios);
        final oid = await other.loadOrCreate(deviceName: 'x');
        expect(Ed25519DeviceIdentityService.isWeakPublicKey(oid.publicKey), isFalse);
      }
      expect(Ed25519DeviceIdentityService.isWeakPublicKey(Uint8List(5)), isFalse,
          reason: 'wrong length is rejected elsewhere, not "weak"');
    });

    test('an empty message can be signed and verified', () async {
      final sig = await s.sign(Uint8List(0));
      expect(await s.verify(message: Uint8List(0), signature: sig, publicKey: id.publicKey), isTrue);
    });

    test('signing before loading the identity is an error', () {
      expect(() => service().sign(bytes('x')), throwsStateError);
    });
  });

  group('failure policy: never silently replace the identity', () {
    test('an unreadable key store throws and creates nothing', () async {
      store.failReads = StateError('keystore locked');
      await expectLater(service().loadOrCreate(deviceName: 'a'), throwsStateError);
      expect(store.data, isEmpty);
      expect(store.writes, 0);
    });

    test('a corrupt stored seed throws and is left untouched', () async {
      final bad = Uint8List.fromList([1, 2, 3]);
      store.data[Ed25519DeviceIdentityService.seedKey] = bad;
      await expectLater(
        service().loadOrCreate(deviceName: 'a'),
        throwsA(isA<HiveError>().having((e) => e.code, 'code', HiveErrorCode.keyUnavailable)),
      );
      expect(store.data[Ed25519DeviceIdentityService.seedKey], bad);
      expect(store.writes, 0);
    });

    test('a failed write on first launch throws instead of returning an unsaved identity', () async {
      store.failWrites = StateError('disk full');
      await expectLater(service().loadOrCreate(deviceName: 'a'), throwsStateError);
    });

    test('after a transient read failure a retry restores the original identity', () async {
      final original = await service().loadOrCreate(deviceName: 'a');
      final s = service();
      store.failReads = StateError('keystore locked');
      await expectLater(s.loadOrCreate(deviceName: 'a'), throwsStateError);
      store.failReads = null;
      final retry = await s.loadOrCreate(deviceName: 'a');
      expect(retry.nodeId, original.nodeId);
    });

    test('the error text never contains key bytes', () async {
      store.data[Ed25519DeviceIdentityService.seedKey] = Uint8List.fromList([9, 8, 7]);
      try {
        await service().loadOrCreate(deviceName: 'a');
        fail('should throw');
      } on HiveError catch (e) {
        expect('${e.message} ${e.technicalDetails}', isNot(contains('9, 8, 7')));
      }
    });
  });
}
