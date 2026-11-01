import '../../shared/models/jobs.dart';
import '../../shared/models/replica_record.dart';

/// Durable state for replication, so process death or an app restart can never
/// turn into false success or a lost job (PRD section 13.1).
abstract interface class ReplicationStore {
  Future<void> saveJob(UploadJob job);
  Future<void> saveReplica(ReplicaRecord replica);

  /// Peers with a replica of [contentId] that passed verification.
  Future<Set<String>> verifiedReplicaNodeIds(String contentId);

  /// Jobs that are neither completed nor failed, to resume after a restart.
  Future<List<UploadJob>> unfinishedJobs();
}
