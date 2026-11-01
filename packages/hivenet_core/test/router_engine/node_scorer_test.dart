import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/peers.dart';

void main() {
  const scorer = DeterministicNodeScorer();

  test('weights match the PRD and sum to 1', () {
    const w = ScoreWeights();
    expect([w.capacity, w.latency, w.reliability, w.bandwidth],
        [0.35, 0.30, 0.20, 0.15]);
    expect(w.total, closeTo(1.0, 1e-9));
  });

  test('the total is the weighted sum of the four components', () {
    final b = scorer.breakdown(peer('a'));
    expect(b.total,
        closeTo(0.35 * b.capacity + 0.30 * b.latency + 0.20 * b.reliability + 0.15 * b.bandwidth, 1e-9));
  });

  test('every component and the total stay within 0..100', () {
    for (final p in [
      peer('a', available: 0, total: 1, latencyMs: 99999, bandwidth: 0, reliability: -5),
      peer('b', available: 99 * gib, total: 1 * gib, latencyMs: 0, bandwidth: 1 << 40, reliability: 500),
      peer('c', total: 0, available: 0),
    ]) {
      final b = scorer.breakdown(p);
      for (final v in [b.capacity, b.latency, b.reliability, b.bandwidth, b.total]) {
        expect(v, inInclusiveRange(0, 100), reason: p.nodeId);
      }
    }
  });

  group('capacity', () {
    test('is the free share of the disk after reservations', () {
      expect(scorer.breakdown(peer('a', total: 100, available: 50)).capacity, 50);
      expect(scorer.breakdown(peer('a', total: 100, available: 50, reserved: 20)).capacity, 30);
    });
    test('never goes negative when reservations exceed free space', () {
      expect(scorer.breakdown(peer('a', total: 100, available: 10, reserved: 40)).capacity, 0);
    });
    test('a peer reporting no total storage scores 0, not NaN', () {
      expect(scorer.breakdown(peer('a', total: 0, available: 0)).capacity, 0);
    });
  });

  group('latency', () {
    test('lower latency scores higher, 0 ms is 100, the ceiling is 0', () {
      expect(scorer.breakdown(peer('a', latencyMs: 0)).latency, 100);
      expect(scorer.breakdown(peer('a', latencyMs: 250)).latency, 50);
      expect(scorer.breakdown(peer('a', latencyMs: 500)).latency, 0);
      expect(scorer.breakdown(peer('a', latencyMs: 9000)).latency, 0);
    });
    test('an unmeasured peer gets the neutral score', () {
      expect(scorer.breakdown(peer('a', latencyMs: null)).latency, 50);
    });
  });

  group('bandwidth', () {
    test('scales up to the target', () {
      expect(scorer.breakdown(peer('a', bandwidth: 6250000)).bandwidth, 50);
      expect(scorer.breakdown(peer('a', bandwidth: 12500000)).bandwidth, 100);
      expect(scorer.breakdown(peer('a', bandwidth: 99999999)).bandwidth, 100);
    });
    test('an unmeasured peer gets the neutral score', () {
      expect(scorer.breakdown(peer('a', bandwidth: null)).bandwidth, 50);
    });
  });

  test('reliability is used as given, clamped', () {
    expect(scorer.breakdown(peer('a', reliability: 73)).reliability, 73);
    expect(scorer.breakdown(peer('a', reliability: 250)).reliability, 100);
  });

  test('a better peer on every axis scores strictly higher', () {
    final good = peer('good', available: 18 * gib, latencyMs: 10, bandwidth: 12000000, reliability: 95);
    final bad = peer('bad', available: 2 * gib, latencyMs: 300, bandwidth: 1000000, reliability: 40);
    expect(scorer.score(good), greaterThan(scorer.score(bad)));
  });

  test('the same input always gives the same score', () {
    final p = peer('a');
    expect(scorer.score(p), scorer.score(p));
  });

  test('custom weights change the ranking', () {
    final lowLatency = peer('fast', latencyMs: 5, available: 1 * gib);
    final roomy = peer('roomy', latencyMs: 400, available: 19 * gib);
    const latencyOnly = DeterministicNodeScorer(ScoreConfig(
        weights: ScoreWeights(capacity: 0, latency: 1, reliability: 0, bandwidth: 0)));
    const capacityOnly = DeterministicNodeScorer(ScoreConfig(
        weights: ScoreWeights(capacity: 1, latency: 0, reliability: 0, bandwidth: 0)));
    expect(latencyOnly.score(lowLatency), greaterThan(latencyOnly.score(roomy)));
    expect(capacityOnly.score(roomy), greaterThan(capacityOnly.score(lowLatency)));
  });
}
