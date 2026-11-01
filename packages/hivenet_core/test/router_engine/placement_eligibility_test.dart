import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/peers.dart';

void main() {
  const request = PlacementRequest(sizeBytes: 5 * 1024 * 1024, importance: Importance.normal);
  const policy = EligibilityPolicy(safetyMarginBytes: 100 * 1024 * 1024);

  EligibilityResult run(List<PeerTelemetry> peers,
          {Set<String>? trusted, PlacementRequest req = request}) =>
      filterEligible(
        request: req,
        candidates: peers,
        trustedNodeIds: trusted ?? {for (final p in peers) p.nodeId},
        now: testNow,
        policy: policy,
      );

  test('a healthy trusted peer is eligible', () {
    final r = run([peer('a')]);
    expect(r.eligible.map((p) => p.nodeId), ['a']);
    expect(r.rejected, isEmpty);
  });

  test('an untrusted peer is rejected even if it is otherwise perfect', () {
    final r = run([peer('stranger')], trusted: {'someone-else'});
    expect(r.rejected['stranger'], {IneligibleReason.notTrusted});
  });

  test('only online peers are eligible', () {
    for (final status in [PeerStatus.offline, PeerStatus.discovered, PeerStatus.temporarilyUnavailable]) {
      final r = run([peer('a', status: status)]);
      expect(r.rejected['a'], contains(IneligibleReason.notOnline), reason: status.name);
    }
  });

  test('stale telemetry is rejected, fresh is accepted', () {
    expect(run([peer('a', age: const Duration(seconds: 14))]).eligible, hasLength(1));
    expect(run([peer('a', age: const Duration(seconds: 16))]).rejected['a'],
        contains(IneligibleReason.staleTelemetry));
  });

  test('an incompatible protocol version is rejected', () {
    expect(run([peer('a', protocolVersion: kProtocolVersion + 1)]).rejected['a'],
        contains(IneligibleReason.incompatibleProtocol));
  });

  test('a peer at the concurrent-transfer limit is overloaded', () {
    expect(run([peer('a', activeTransfers: 1)]).eligible, hasLength(1));
    expect(run([peer('a', activeTransfers: 2)]).rejected['a'],
        contains(IneligibleReason.overloaded));
  });

  group('storage', () {
    test('needs room for the object plus the safety margin', () {
      const margin = 100 * 1024 * 1024;
      final size = request.sizeBytes;
      expect(run([peer('fits', available: size + margin)]).eligible, hasLength(1));
      expect(run([peer('tight', available: size + margin - 1)]).rejected['tight'],
          contains(IneligibleReason.insufficientStorage));
    });

    test('space already reserved for other uploads does not count as free', () {
      final r = run([peer('a', available: 1 * gib, reserved: 1 * gib)]);
      expect(r.rejected['a'], contains(IneligibleReason.insufficientStorage));
    });
  });

  group('battery', () {
    test('below the minimum and not charging is rejected', () {
      expect(run([peer('a', battery: 14)]).rejected['a'], contains(IneligibleReason.lowBattery));
      expect(run([peer('a', battery: 15)]).eligible, hasLength(1), reason: 'at the minimum is fine');
    });
    test('charging overrides a low level', () {
      expect(run([peer('a', battery: 3, charging: true)]).eligible, hasLength(1));
    });
    test('unknown is not rejected', () {
      expect(run([peer('a', battery: null)]).eligible, hasLength(1));
    });
  });

  test('excluded nodes are rejected', () {
    final r = run([peer('self'), peer('other')],
        req: const PlacementRequest(
            sizeBytes: 1024, importance: Importance.normal, excludeNodeIds: {'self'}));
    expect(r.eligible.map((p) => p.nodeId), ['other']);
    expect(r.rejected['self'], {IneligibleReason.excluded});
  });

  test('every failing reason is reported, not just the first', () {
    final r = run([
      peer('bad', status: PeerStatus.offline, activeTransfers: 5, available: 0, age: const Duration(minutes: 5)),
    ], trusted: {});
    expect(r.rejected['bad'], {
      IneligibleReason.notTrusted,
      IneligibleReason.notOnline,
      IneligibleReason.staleTelemetry,
      IneligibleReason.overloaded,
      IneligibleReason.insufficientStorage,
    });
  });

  test('the input list is not modified and the result keeps input order', () {
    final peers = [peer('c'), peer('a'), peer('b')];
    final r = run(peers);
    expect(r.eligible.map((p) => p.nodeId), ['c', 'a', 'b']);
    expect(peers.map((p) => p.nodeId), ['c', 'a', 'b']);
  });

  test('EligibilityPolicy.fromNetwork follows the network config', () {
    final p = EligibilityPolicy.fromNetwork(const NetworkConfig());
    expect(p.maxTelemetryAge, const Duration(seconds: 15));
    expect(p.maxActiveTransfers, 2);
  });
}
