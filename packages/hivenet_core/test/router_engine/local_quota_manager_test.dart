import 'dart:async';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  var stored = 0;
  int? freeDisk;

  LocalQuotaManager manager({
    int quota = 1000,
    int margin = 0,
    Duration ttl = const Duration(minutes: 10),
    bool withDisk = false,
  }) =>
      LocalQuotaManager(
        quotaBytes: quota,
        storedBytes: () async => stored,
        freeDiskBytes: withDisk ? () async => freeDisk : null,
        safetyMarginBytes: margin,
        reservationTtl: ttl,
        clock: () => now,
      );

  setUp(() {
    now = DateTime.utc(2026, 11, 1, 12);
    stored = 0;
    freeDisk = null;
  });

  group('reserving', () {
    test('accepts a reservation that fits and tracks it', () async {
      final q = manager();
      expect(await q.tryReserve('a', 400), isTrue);
      expect(await q.reservedBytes, 400);
    });

    test('can reserve exactly the whole quota, not one byte more', () async {
      final q = manager();
      expect(await q.tryReserve('a', 1000), isTrue);
      expect(await q.tryReserve('b', 1), isFalse);
    });

    test('bytes already stored count against the quota', () async {
      stored = 700;
      final q = manager();
      expect(await q.tryReserve('a', 301), isFalse);
      expect(await q.tryReserve('a', 300), isTrue);
    });

    test('reservations add up across uploads', () async {
      final q = manager();
      expect(await q.tryReserve('a', 600), isTrue);
      expect(await q.tryReserve('b', 400), isTrue);
      expect(await q.tryReserve('c', 1), isFalse);
      expect(await q.reservedBytes, 1000);
    });

    test('a refused reservation reserves nothing', () async {
      final q = manager();
      await q.tryReserve('a', 900);
      expect(await q.tryReserve('b', 200), isFalse);
      expect(await q.reservedBytes, 900);
    });

    test('rejects zero and negative sizes', () {
      final q = manager();
      expect(() => q.tryReserve('a', 0), throwsArgumentError);
      expect(() => q.tryReserve('a', -5), throwsArgumentError);
    });

    test('a zero quota refuses everything', () async {
      expect(await manager(quota: 0).tryReserve('a', 1), isFalse);
    });
  });

  group('atomicity', () {
    test('concurrent reservations can never over-allocate', () async {
      // Quota 1000: exactly 5 of these 20 requests of 200 bytes can win.
      //
      // Every caller waits on the same gate and is released at the same moment.
      // That interleaves them the way simultaneous incoming uploads would, and
      // is what lets a check-then-insert implementation hand the last bytes to
      // several callers. (Staggered timers would hide the race.)
      final gate = Completer<void>();
      final q = LocalQuotaManager(
        quotaBytes: 1000,
        storedBytes: () async {
          await gate.future;
          return 0;
        },
        safetyMarginBytes: 0,
        clock: () => now,
      );
      final pending = [
        for (var i = 0; i < 20; i++) q.tryReserve('r$i', 200),
      ];
      gate.complete();
      final results = await Future.wait(pending);
      expect(results.where((ok) => ok), hasLength(5));
      expect(await q.reservedBytes, 1000);
    });

    test('a throwing lookup does not wedge later reservations', () async {
      var fail = true;
      final q = LocalQuotaManager(
        quotaBytes: 1000,
        storedBytes: () async {
          if (fail) throw StateError('disk error');
          return 0;
        },
        safetyMarginBytes: 0,
        clock: () => now,
      );
      await expectLater(q.tryReserve('a', 10), throwsStateError);
      fail = false;
      expect(await q.tryReserve('a', 10), isTrue);
    });
  });

  group('retries and release', () {
    test('re-reserving the same id replaces it instead of double counting', () async {
      final q = manager();
      expect(await q.tryReserve('a', 600), isTrue);
      expect(await q.tryReserve('a', 600), isTrue);
      expect(await q.reservedBytes, 600);
    });

    test('a failed re-reserve keeps the original reservation', () async {
      final q = manager();
      await q.tryReserve('a', 600);
      expect(await q.tryReserve('a', 5000), isFalse);
      expect(await q.reservedBytes, 600);
    });

    test('release frees the space and is safe to repeat', () async {
      final q = manager();
      await q.tryReserve('a', 1000);
      await q.release('a');
      await q.release('a');
      await q.release('never-existed');
      expect(await q.reservedBytes, 0);
      expect(await q.tryReserve('b', 1000), isTrue);
    });
  });

  group('expiry', () {
    test('an abandoned reservation frees its space after the TTL', () async {
      final q = manager(ttl: const Duration(minutes: 5));
      await q.tryReserve('a', 1000);
      now = now.add(const Duration(minutes: 4));
      expect(await q.tryReserve('b', 1), isFalse);
      now = now.add(const Duration(minutes: 2));
      expect(await q.tryReserve('b', 1000), isTrue);
    });

    test('an expired reservation can no longer commit', () async {
      final q = manager(ttl: const Duration(minutes: 5));
      await q.tryReserve('a', 100);
      expect(await q.canCommit('a'), isTrue);
      now = now.add(const Duration(minutes: 6));
      expect(await q.canCommit('a'), isFalse);
    });
  });

  group('canCommit', () {
    test('is false for an unknown reservation', () async {
      expect(await manager().canCommit('nope'), isFalse);
    });

    test('is false if other data arrived and the quota no longer fits', () async {
      final q = manager();
      await q.tryReserve('a', 600);
      expect(await q.canCommit('a'), isTrue);
      stored = 500; // something else was stored meanwhile
      expect(await q.canCommit('a'), isFalse);
    });

    test('does not change the reservation', () async {
      final q = manager();
      await q.tryReserve('a', 600);
      await q.canCommit('a');
      expect(await q.reservedBytes, 600);
    });
  });

  group('disk safety margin', () {
    test('keeps free space for the OS when real free space is known', () async {
      freeDisk = 5000;
      final q = manager(quota: 100000, margin: 1000, withDisk: true);
      expect(await q.tryReserve('a', 4000), isTrue);
      expect(await q.tryReserve('b', 1), isFalse, reason: '5000 - 4000 - 1 < margin');
    });

    test('allows exactly down to the margin', () async {
      freeDisk = 5000;
      final q = manager(quota: 100000, margin: 1000, withDisk: true);
      expect(await q.tryReserve('a', 4000), isTrue);
    });

    test('is re-checked at commit time if the disk filled up meanwhile', () async {
      freeDisk = 5000;
      final q = manager(quota: 100000, margin: 1000, withDisk: true);
      await q.tryReserve('a', 3000);
      expect(await q.canCommit('a'), isTrue);
      freeDisk = 3500; // another app used the space
      expect(await q.canCommit('a'), isFalse);
    });

    test('is skipped, not failed, when free space is unknown', () async {
      freeDisk = null;
      final q = manager(quota: 100, margin: 1 << 40, withDisk: true);
      expect(await q.tryReserve('a', 50), isTrue);
    });
  });
}
