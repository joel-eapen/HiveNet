import 'dart:async';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/peers.dart';

class _FakeModel implements DecisionModelAdapter {
  _FakeModel(this.answer);
  final Future<List<String>> Function(List<PeerTelemetry> eligible) answer;
  int calls = 0;
  List<String>? sawIds;

  @override
  Future<List<String>> rank(PlacementRequest request, List<PeerTelemetry> eligible) {
    calls++;
    sawIds = [for (final p in eligible) p.nodeId];
    return answer(eligible);
  }
}

void main() {
  const normal = PlacementRequest(sizeBytes: 2 * 1024 * 1024, importance: Importance.normal);
  const important = PlacementRequest(sizeBytes: 2 * 1024 * 1024, importance: Importance.important);
  const margin = EligibilityPolicy(safetyMarginBytes: 0);

  DeterministicStorageRouter router({
    Set<String>? trusted,
    DecisionModelAdapter? model,
    Duration modelTimeout = const Duration(milliseconds: 200),
    void Function(PlacementAudit)? onAudit,
  }) =>
      DeterministicStorageRouter(
        trustedNodeIds: () async => trusted ?? {'a', 'b', 'c', 'd', 'e'},
        decisionModel: model,
        policy: margin,
        modelTimeout: modelTimeout,
        clock: () => testNow,
        onAudit: onAudit,
      );

  // a is best, then b, then c.
  List<PeerTelemetry> three() => [
        peer('c', latencyMs: 300, available: 4 * gib, reliability: 50),
        peer('a', latencyMs: 5, available: 18 * gib, reliability: 99),
        peer('b', latencyMs: 60, available: 12 * gib, reliability: 80),
      ];

  group('deterministic placement', () {
    test('picks the best two peers for a normal image, best first', () async {
      final plan = await router().plan(normal, three());
      expect(plan.targetNodeIds, ['a', 'b']);
      expect(plan.desiredReplicas, 2);
      expect(plan.isShortfall, isFalse);
    });

    test('an important image asks for three replicas', () async {
      final plan = await router().plan(important, three());
      expect(plan.targetNodeIds, ['a', 'b', 'c']);
      expect(plan.desiredReplicas, 3);
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
      final twins = [peer('z'), peer('m'), peer('q')];
      final plan = await router(trusted: {'z', 'm', 'q'}).plan(normal, twins);
      expect(plan.targetNodeIds, ['m', 'q']);
    });

    test('never selects the same device twice, even if reported twice', () async {
      final dup = [peer('a'), peer('a', age: const Duration(seconds: 1)), peer('b')];
      final plan = await router().plan(normal, dup);
      expect(plan.targetNodeIds, ['a', 'b']);
    });
  });

  group('hard constraints', () {
    test('skips untrusted, offline, stale, full and overloaded peers', () async {
      final peers = [
        peer('a'),
        peer('b', status: PeerStatus.temporarilyUnavailable),
        peer('c', age: const Duration(minutes: 3)),
        peer('d', available: 1024),
        peer('e', activeTransfers: 9),
        peer('stranger'),
      ];
      final plan = await router(trusted: {'a', 'b', 'c', 'd', 'e'}).plan(normal, peers);
      expect(plan.targetNodeIds, ['a']);
      expect(plan.isShortfall, isTrue);
      expect(plan.audit!.rejected.keys, containsAll(['b', 'c', 'd', 'e', 'stranger']));
    });

    test('a peer revoked since the last plan is not selected', () async {
      var trusted = {'a', 'b', 'c'};
      final r = DeterministicStorageRouter(
          trustedNodeIds: () async => trusted, policy: margin, clock: () => testNow);
      expect((await r.plan(normal, three())).targetNodeIds, ['a', 'b']);
      trusted = {'b', 'c'};
      expect((await r.plan(normal, three())).targetNodeIds, ['b', 'c']);
    });

    test('excluded nodes (for example this device) are never chosen', () async {
      final plan = await router().plan(
        const PlacementRequest(
            sizeBytes: 1024, importance: Importance.normal, excludeNodeIds: {'a'}),
        three(),
      );
      expect(plan.targetNodeIds, isNot(contains('a')));
    });
  });

  group('decision model', () {
    test('a valid recommendation reorders the eligible peers', () async {
      final model = _FakeModel((_) async => ['c', 'b', 'a']);
      final plan = await router(model: model).plan(normal, three());
      expect(plan.targetNodeIds, ['c', 'b']);
      expect(plan.audit!.modelOutcome, ModelOutcome.accepted);
      expect(plan.audit!.deterministicOrder, ['a', 'b', 'c']);
    });

    test('a partial recommendation is completed in score order', () async {
      final model = _FakeModel((_) async => ['c']);
      final plan = await router(model: model).plan(important, three());
      expect(plan.targetNodeIds, ['c', 'a', 'b']);
    });

    test('the model only ever sees peers that passed the hard filter', () async {
      final model = _FakeModel((e) async => [for (final p in e) p.nodeId]);
      await router(model: model).plan(normal, [
        ...three(),
        peer('d', status: PeerStatus.offline),
        peer('e', available: 10),
      ]);
      expect(model.sawIds, unorderedEquals(['a', 'b', 'c']));
    });

    test('recommending an ineligible peer discards the recommendation', () async {
      final model = _FakeModel((_) async => ['d', 'a']);
      final plan = await router(model: model).plan(
        normal,
        [...three(), peer('d', status: PeerStatus.offline)],
      );
      expect(plan.targetNodeIds, ['a', 'b'], reason: 'fell back to score order');
      expect(plan.audit!.modelOutcome, ModelOutcome.rejectedInvalid);
      expect(plan.audit!.modelRecommendation, ['d', 'a']);
    });

    test('recommending a peer that does not exist is rejected', () async {
      final model = _FakeModel((_) async => ['ghost', 'a']);
      final plan = await router(model: model).plan(normal, three());
      expect(plan.targetNodeIds, ['a', 'b']);
      expect(plan.audit!.modelOutcome, ModelOutcome.rejectedInvalid);
    });

    test('a recommendation naming a peer twice is rejected', () async {
      final model = _FakeModel((_) async => ['c', 'c', 'b']);
      final plan = await router(model: model).plan(normal, three());
      expect(plan.targetNodeIds, ['a', 'b']);
      expect(plan.audit!.modelOutcome, ModelOutcome.rejectedInvalid);
    });

    test('a model that throws never blocks the upload', () async {
      final model = _FakeModel((_) async => throw StateError('endpoint down'));
      final plan = await router(model: model).plan(normal, three());
      expect(plan.targetNodeIds, ['a', 'b']);
      expect(plan.audit!.modelOutcome, ModelOutcome.failed);
    });

    test('a model that is too slow is abandoned after the timeout', () async {
      final model = _FakeModel((_) => Completer<List<String>>().future); // never answers
      final sw = Stopwatch()..start();
      final plan = await router(model: model, modelTimeout: const Duration(milliseconds: 100))
          .plan(normal, three());
      sw.stop();
      expect(plan.targetNodeIds, ['a', 'b']);
      expect(plan.audit!.modelOutcome, ModelOutcome.timedOut);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('the model is not consulted when there is nothing to choose between', () async {
      final model = _FakeModel((_) async => ['a']);
      await router(model: model).plan(normal, [peer('a')]);
      expect(model.calls, 0);
    });

    test('no model configured means the deterministic order, reported as such', () async {
      final plan = await router().plan(normal, three());
      expect(plan.audit!.modelOutcome, ModelOutcome.notUsed);
    });
  });

  group('audit', () {
    test('records the input, rejections, order and final selection', () async {
      PlacementAudit? seen;
      final plan = await router(onAudit: (a) => seen = a).plan(
        normal,
        [...three(), peer('d', status: PeerStatus.offline)],
      );
      expect(seen, same(plan.audit));
      final audit = plan.audit!;
      expect(audit.inputSnapshot.map((p) => p.nodeId), containsAll(['a', 'b', 'c', 'd']));
      expect(audit.rejected['d'], {IneligibleReason.notOnline});
      expect(audit.selected, ['a', 'b']);
      expect(audit.sizeBytes, normal.sizeBytes);
      expect(audit.createdAt, testNow);
    });

    test('serialises to JSON without any image content', () async {
      final plan = await router().plan(normal, three());
      final json = plan.audit!.toJson();
      expect(json['selected'], ['a', 'b']);
      expect(json['modelOutcome'], 'notUsed');
      expect(json.keys, isNot(contains('bytes')));
      expect(json.keys, isNot(contains('image')));
    });
  });
}
