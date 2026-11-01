import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/peers.dart';

void main() {
  const normal = PlacementRequest(sizeBytes: 2 * 1024 * 1024, importance: Importance.normal);
  const important = PlacementRequest(sizeBytes: 2 * 1024 * 1024, importance: Importance.important);
  const noMargin = EligibilityPolicy(safetyMarginBytes: 0);

  DeterministicStorageRouter router({
    Set<String>? trusted,
    EligibilityPolicy policy = noMargin,
    NodeScorer? scorer,
    void Function(PlacementAudit)? onAudit,
  }) =>
      DeterministicStorageRouter(
        trustedNodeIds: () async => trusted ?? {'a', 'b', 'c', 'd', 'e'},
        policy: policy,
        scorer: scorer,
        clock: () => testNow,
        onAudit: onAudit,
      );

  // a is clearly best, then b, then c.
  List<PeerTelemetry> three() => [
        peer('c', latencyMs: 300, available: 4 * gib, reliability: 50, battery: 40),
        peer('a', latencyMs: 5, available: 18 * gib, reliability: 99, battery: 95, charging: true),
        peer('b', latencyMs: 60, available: 12 * gib, reliability: 80, battery: 70),
      ];

  group('choosing by score', () {
    test('picks the best two peers for a normal image, best first', () async {
      final plan = await router().plan(normal, three());
      expect(plan.targetNodeIds, ['a', 'b']);
      expect(plan.desiredReplicas, 2);
      expect(plan.isShortfall, isFalse);
    });

    test('an important image asks for three replicas', () async {
      final plan = await router().plan(important, three());
      expect(plan.targetNodeIds, ['a', 'b', 'c']);
      expect(plan.isShortfall, isFalse);
    });

    test('flags a shortfall instead of pretending', () async {
      final plan = await router().plan(important, [peer('a'), peer('b')]);
      expect(plan.targetNodeIds, hasLength(2));
      expect(plan.isShortfall, isTrue);
    });

    test('no candidates gives an empty plan that is a shortfall', () async {
      final plan = await router().plan(normal, []);
      expect(plan.targetNodeIds, isEmpty);
      expect(plan.isShortfall, isTrue);
    });

    test('is deterministic regardless of input order', () async {
      final input = three();
      final forwards = await router().plan(normal, input);
      final backwards = await router().plan(normal, input.reversed.toList());
      expect(backwards.targetNodeIds, forwards.targetNodeIds);
    });

    test('equal scores are broken by node id, not by input order', () async {
      final plan = await router(trusted: {'z', 'm', 'q'}).plan(normal, [peer('z'), peer('m'), peer('q')]);
      expect(plan.targetNodeIds, ['m', 'q']);
    });

    test('never selects the same device twice, even if reported twice', () async {
      final dup = [peer('a'), peer('a', age: const Duration(seconds: 1)), peer('b')];
      final plan = await router().plan(normal, dup);
      expect(plan.targetNodeIds, ['a', 'b']);
    });
  });

  group('the score decides, factor by factor', () {
    // Two peers identical except for one thing: the winner must be the better one.
    Future<List<String>> pick(PeerTelemetry better, PeerTelemetry worse) async {
      final plan = await router(trusted: {better.nodeId, worse.nodeId}).plan(
        const PlacementRequest(sizeBytes: 1024, importance: Importance.normal),
        [worse, better],
      );
      return plan.audit!.ranking;
    }

    test('more free storage wins', () async {
      expect((await pick(peer('more', available: 16 * gib), peer('less', available: 3 * gib))).first, 'more');
    });
    test('lower latency wins', () async {
      expect((await pick(peer('quick', latencyMs: 10), peer('slow', latencyMs: 400))).first, 'quick');
    });
    test('more battery wins', () async {
      expect((await pick(peer('full', battery: 90), peer('low', battery: 30))).first, 'full');
    });
    test('a plugged-in phone beats one on battery', () async {
      expect((await pick(peer('plugged', battery: 50, charging: true), peer('unplugged', battery: 50, charging: false))).first, 'plugged');
    });
    test('better observed uptime wins', () async {
      expect((await pick(peer('steady', reliability: 99), peer('flaky', reliability: 30))).first, 'steady');
    });
    test('a longer-running app wins', () async {
      expect((await pick(peer('settled', uptimeSeconds: 3600), peer('fresh', uptimeSeconds: 20))).first, 'settled');
    });
    test('an idle peer beats a busy one', () async {
      expect((await pick(peer('idle', activeTransfers: 0), peer('busy', activeTransfers: 1))).first, 'idle');
    });
    test('higher bandwidth wins', () async {
      expect((await pick(peer('fast', bandwidth: 12000000), peer('slowline', bandwidth: 800000))).first, 'fast');
    });

    test('a strong all-rounder beats a peer that is only good at one thing', () async {
      final specialist = peer('specialist', latencyMs: 2, available: 19 * gib, battery: 8, reliability: 30, uptimeSeconds: 10);
      final allRounder = peer('allrounder', latencyMs: 90, available: 11 * gib, battery: 85, reliability: 95, uptimeSeconds: 3000);
      final ranking = await pick(allRounder, specialist);
      expect(ranking.first, 'allrounder');
    });

    test('a custom scorer changes the outcome', () async {
      const batteryOnly = DeterministicNodeScorer(ScoreConfig(
          weights: ScoreWeights(capacity: 0, latency: 0, battery: 1, uptime: 0, bandwidth: 0, load: 0)));
      final peers = [peer('fast', latencyMs: 1, battery: 30), peer('full', latencyMs: 450, battery: 100)];
      final plan = await router(trusted: {'fast', 'full'}, scorer: batteryOnly).plan(
          const PlacementRequest(sizeBytes: 1024, importance: Importance.normal), peers);
      expect(plan.audit!.ranking.first, 'full');
    });
  });

  group('hard constraints come before the score', () {
    test('skips untrusted, offline, stale, full and overloaded peers', () async {
      final peers = [
        peer('a'),
        peer('b', status: PeerStatus.temporarilyUnavailable),
        peer('c', age: const Duration(minutes: 3)),
        peer('d', available: 1024),
        peer('e', activeTransfers: 9),
        peer('stranger'),
      ];
      final plan = await router().plan(normal, peers);
      expect(plan.targetNodeIds, ['a']);
      expect(plan.isShortfall, isTrue);
      expect(plan.audit!.rejected.keys, containsAll(['b', 'c', 'd', 'e', 'stranger']));
    });

    test('a nearly empty phone is ruled out however good its other numbers are', () async {
      final dying = peer('dying', battery: 8, latencyMs: 1, available: 19 * gib, reliability: 100, uptimeSeconds: 3600);
      final plan = await router(trusted: {'dying', 'ok'}).plan(normal, [dying, peer('ok', battery: 60)]);
      expect(plan.targetNodeIds, ['ok']);
      expect(plan.audit!.rejected['dying'], contains(IneligibleReason.lowBattery));
    });

    test('a low phone that is charging is fine', () async {
      final plan = await router(trusted: {'p'}).plan(normal, [peer('p', battery: 8, charging: true)]);
      expect(plan.targetNodeIds, ['p']);
    });

    test('an unknown battery level is not held against a peer', () async {
      final plan = await router(trusted: {'p'}).plan(normal, [peer('p', battery: null)]);
      expect(plan.targetNodeIds, ['p']);
    });

    test('a revoked device stops being chosen on the next plan', () async {
      var trusted = {'a', 'b', 'c'};
      final r = DeterministicStorageRouter(
          trustedNodeIds: () async => trusted, policy: noMargin, clock: () => testNow);
      expect((await r.plan(normal, three())).targetNodeIds, ['a', 'b']);
      trusted = {'b', 'c'};
      expect((await r.plan(normal, three())).targetNodeIds, ['b', 'c']);
    });

    test('excluded nodes (for example this device) are never chosen', () async {
      final plan = await router().plan(
        const PlacementRequest(sizeBytes: 1024, importance: Importance.normal, excludeNodeIds: {'a'}),
        three(),
      );
      expect(plan.targetNodeIds, isNot(contains('a')));
    });
  });

  group('audit', () {
    test('explains the decision: scores, ranking, who was ruled out and why', () async {
      PlacementAudit? seen;
      final plan = await router(onAudit: (a) => seen = a).plan(
        normal,
        [...three(), peer('d', status: PeerStatus.offline)],
      );
      final audit = plan.audit!;
      expect(seen, same(audit));
      expect(audit.ranking, ['a', 'b', 'c']);
      expect(audit.selected, ['a', 'b']);
      expect(audit.rejected['d'], {IneligibleReason.notOnline});
      expect(audit.scores.keys, unorderedEquals(['a', 'b', 'c']), reason: 'scored only the eligible');
      expect(audit.scores['a']!.total, greaterThan(audit.scores['b']!.total));
      expect(audit.scores['b']!.total, greaterThan(audit.scores['c']!.total));
      expect(audit.createdAt, testNow);
    });

    test('serialises to JSON without any image content', () async {
      final json = (await router().plan(normal, three())).audit!.toJson();
      expect(json['selected'], ['a', 'b']);
      expect((json['scores']! as Map).keys, containsAll(['a', 'b', 'c']));
      expect(json.keys, isNot(contains('bytes')));
      expect(json.keys, isNot(contains('image')));
      expect(json.keys, isNot(contains('model')));
    });
  });
}
