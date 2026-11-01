import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/peers.dart';

void main() {
  const scorer = DeterministicNodeScorer();

  test('weights add up to 1', () {
    expect(const ScoreWeights().total, closeTo(1.0, 1e-9));
  });

  test('the total is the weighted sum of the factors', () {
    final b = scorer.breakdown(peer('a', battery: 80, uptimeSeconds: 1800));
    const w = ScoreWeights();
    expect(
        b.total,
        closeTo(
            w.capacity * b.capacity +
                w.latency * b.latency +
                w.battery * b.battery +
                w.uptime * b.uptime +
                w.bandwidth * b.bandwidth +
                w.load * b.load,
            1e-9));
  });

  test('every factor and the total stay within 0..100', () {
    for (final p in [
      peer('a', available: 0, total: 1, latencyMs: 99999, bandwidth: 0, reliability: -5, battery: -3, activeTransfers: 99, uptimeSeconds: -10),
      peer('b', available: 99 * gib, total: 1 * gib, latencyMs: 0, bandwidth: 1 << 40, reliability: 500, battery: 900, uptimeSeconds: 1 << 40),
      peer('c', total: 0, available: 0),
    ]) {
      final b = scorer.breakdown(p);
      for (final v in [b.capacity, b.latency, b.battery, b.uptime, b.bandwidth, b.load, b.total]) {
        expect(v, inInclusiveRange(0, 100), reason: p.nodeId);
      }
    }
  });

  test('the same input always gives the same score', () {
    final p = peer('a', battery: 60, uptimeSeconds: 100);
    expect(scorer.score(p), scorer.score(p));
  });

  group('capacity', () {
    test('is the free share of the shared space after reservations', () {
      expect(scorer.breakdown(peer('a', total: 100, available: 50)).capacity, 50);
      expect(scorer.breakdown(peer('a', total: 100, available: 50, reserved: 20)).capacity, 30);
    });
    test('never goes negative; a peer reporting no total scores 0, not NaN', () {
      expect(scorer.breakdown(peer('a', total: 100, available: 10, reserved: 40)).capacity, 0);
      expect(scorer.breakdown(peer('a', total: 0, available: 0)).capacity, 0);
    });
  });

  group('latency', () {
    test('lower is better: 0 ms is 100, the ceiling and beyond is 0', () {
      expect(scorer.breakdown(peer('a', latencyMs: 0)).latency, 100);
      expect(scorer.breakdown(peer('a', latencyMs: 250)).latency, 50);
      expect(scorer.breakdown(peer('a', latencyMs: 9000)).latency, 0);
    });
    test('unmeasured is neutral', () {
      expect(scorer.breakdown(peer('a', latencyMs: null)).latency, 50);
    });
  });

  group('battery', () {
    test('plugged in is a perfect score whatever the level', () {
      expect(scorer.breakdown(peer('a', battery: 5, charging: true)).battery, 100);
    });
    test('on battery it follows the level', () {
      expect(scorer.breakdown(peer('a', battery: 80, charging: false)).battery, 80);
      expect(scorer.breakdown(peer('a', battery: 40)).battery, 40);
    });
    test('a nearly empty phone is penalized harder than the level alone', () {
      expect(scorer.breakdown(peer('a', battery: 19)).battery, 9.5);
      expect(scorer.breakdown(peer('a', battery: 20)).battery, 20);
    });
    test('unknown is neutral', () {
      expect(scorer.breakdown(peer('a', battery: null)).battery, 50);
    });
  });

  group('uptime', () {
    test('blends answered checks (70%) with how long the app has been running (30%)', () {
      // observed 100, session at the 1h target = 100  ->  100
      expect(scorer.breakdown(peer('a', reliability: 100, uptimeSeconds: 3600)).uptime, 100);
      // observed 100, session 0  ->  70
      expect(scorer.breakdown(peer('a', reliability: 100, uptimeSeconds: 0)).uptime, closeTo(70, 1e-9));
      // observed 0, session full  ->  30
      expect(scorer.breakdown(peer('a', reliability: 0, uptimeSeconds: 3600)).uptime, closeTo(30, 1e-9));
    });
    test('uses whichever half is known, and neutral if neither', () {
      expect(scorer.breakdown(peer('a', reliability: 80, uptimeSeconds: null)).uptime, 80);
      expect(scorer.breakdown(peer('a', reliability: null, uptimeSeconds: 1800)).uptime, 50);
      expect(scorer.breakdown(peer('a', reliability: null, uptimeSeconds: null)).uptime, 50);
    });
    test('a peer that just restarted scores lower than a settled one', () {
      final fresh = scorer.breakdown(peer('a', reliability: 90, uptimeSeconds: 30)).uptime;
      final settled = scorer.breakdown(peer('a', reliability: 90, uptimeSeconds: 3600)).uptime;
      expect(settled, greaterThan(fresh));
    });
  });

  group('bandwidth and load', () {
    test('bandwidth scales up to the target', () {
      expect(scorer.breakdown(peer('a', bandwidth: 6250000)).bandwidth, 50);
      expect(scorer.breakdown(peer('a', bandwidth: 99999999)).bandwidth, 100);
      expect(scorer.breakdown(peer('a', bandwidth: null)).bandwidth, 50);
    });
    test('an idle peer beats a busy one', () {
      expect(scorer.breakdown(peer('a', activeTransfers: 0)).load, 100);
      expect(scorer.breakdown(peer('a', activeTransfers: 1)).load, 50);
      expect(scorer.breakdown(peer('a', activeTransfers: 2)).load, 0);
    });
  });

  group('ranking behaviour', () {
    test('better on every axis scores strictly higher', () {
      final good = peer('good', available: 18 * gib, latencyMs: 10, bandwidth: 12000000,
          reliability: 95, battery: 90, charging: true, uptimeSeconds: 3600);
      final bad = peer('bad', available: 2 * gib, latencyMs: 300, bandwidth: 1000000,
          reliability: 40, battery: 25, uptimeSeconds: 60, activeTransfers: 1);
      expect(scorer.score(good), greaterThan(scorer.score(bad)));
    });

    test('a charging phone beats an otherwise identical one on battery', () {
      final plugged = peer('p', battery: 60, charging: true);
      final unplugged = peer('u', battery: 60, charging: false);
      expect(scorer.score(plugged), greaterThan(scorer.score(unplugged)));
    });

    test('a flaky phone loses to a steady one with the same storage', () {
      final steady = peer('s', reliability: 98, uptimeSeconds: 3000);
      final flaky = peer('f', reliability: 40, uptimeSeconds: 3000);
      expect(scorer.score(steady), greaterThan(scorer.score(flaky)));
    });

    test('custom weights change the ranking', () {
      final fast = peer('fast', latencyMs: 5, battery: 30);
      final fullBattery = peer('full', latencyMs: 400, battery: 100);
      const latencyOnly = DeterministicNodeScorer(ScoreConfig(
          weights: ScoreWeights(capacity: 0, latency: 1, battery: 0, uptime: 0, bandwidth: 0, load: 0)));
      const batteryOnly = DeterministicNodeScorer(ScoreConfig(
          weights: ScoreWeights(capacity: 0, latency: 0, battery: 1, uptime: 0, bandwidth: 0, load: 0)));
      expect(latencyOnly.score(fast), greaterThan(latencyOnly.score(fullBattery)));
      expect(batteryOnly.score(fullBattery), greaterThan(batteryOnly.score(fast)));
    });
  });
}
