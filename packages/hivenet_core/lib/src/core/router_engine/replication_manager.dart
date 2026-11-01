import '../../shared/models/jobs.dart';
import 'storage_router.dart';

/// Coordinates reserve -> transfer -> verify -> commit for each target, and
/// repairs under-replicated objects (PRD FR-04, FR-06, FR-11, §13.1).
///
/// A replica counts only after the destination wrote the full object, verified
/// its hash and committed it durably. Retries are idempotent by
/// jobId/transferId and contentId.
abstract interface class ReplicationManager {
  /// Runs a persisted upload job against [plan]. Emits each state change.
  Stream<UploadJob> replicate(UploadJob job, PlacementPlan plan);

  /// Schedules repair for under-replicated objects using the same
  /// verification and commit path as a normal upload.
  Future<void> repairUnderReplicated();
}

class UnimplementedReplicationManager implements ReplicationManager {
  const UnimplementedReplicationManager();

  @override
  Stream<UploadJob> replicate(UploadJob job, PlacementPlan plan) =>
      throw UnimplementedError('ReplicationManager: Milestone 4');

  @override
  Future<void> repairUnderReplicated() =>
      throw UnimplementedError('ReplicationManager: Milestone 7');
}
