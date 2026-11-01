import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  test('happy path is allowed in order', () {
    const path = [
      UploadState.created, UploadState.reserving, UploadState.transferring,
      UploadState.verifying, UploadState.committing, UploadState.replicating,
      UploadState.completed,
    ];
    for (var i = 0; i < path.length - 1; i++) {
      expect(path[i].canTransitionTo(path[i + 1]), isTrue,
          reason: '${path[i]} -> ${path[i + 1]}');
    }
  });

  test('completed is reachable only from replicating (no false success)', () {
    for (final s in UploadState.values) {
      expect(s.canTransitionTo(UploadState.completed),
          s == UploadState.replicating,
          reason: '$s -> completed');
    }
  });

  test('every in-flight state can fail or retry', () {
    for (final s in [
      UploadState.reserving, UploadState.transferring, UploadState.verifying,
      UploadState.committing, UploadState.replicating,
    ]) {
      expect(s.canTransitionTo(UploadState.failed), isTrue, reason: '$s');
      expect(s.canTransitionTo(UploadState.retryPending), isTrue, reason: '$s');
    }
  });

  test('completed and failed are terminal', () {
    expect(UploadState.completed.isTerminal, isTrue);
    expect(UploadState.failed.isTerminal, isTrue);
    expect(UploadState.underReplicated.isTerminal, isFalse);
  });

  test('UploadJob.transitionTo rejects illegal jumps', () {
    final job = UploadJob(
      jobId: 'j1',
      status: UploadState.created,
      requestedReplicationFactor: 2,
      createdAt: DateTime.utc(2026),
    );
    expect(() => job.transitionTo(UploadState.completed), throwsStateError);
    final next = job.transitionTo(UploadState.reserving);
    expect(next.status, UploadState.reserving);
  });
}
