import 'package:drift/drift.dart';

import '../core/router_engine/replication_store.dart';
import '../shared/models/enums.dart';
import '../shared/models/jobs.dart';
import '../shared/models/replica_record.dart';
import 'app_database.dart';

/// [ReplicationStore] backed by the `upload_jobs` and `replicas` tables.
class DriftReplicationStore implements ReplicationStore {
  DriftReplicationStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> saveJob(UploadJob job) => _db.uploadJobsDao.upsert(
        UploadJobsCompanion.insert(
          jobId: job.jobId,
          status: job.status.wire,
          requestedReplicationFactor: job.requestedReplicationFactor,
          createdAt: job.createdAt,
          contentId: Value(job.contentId),
          completedAt: Value(job.completedAt),
          failureReason: Value(job.failureReason),
        ),
      );

  @override
  Future<void> saveReplica(ReplicaRecord replica) => _db.replicasDao.upsert(
        ReplicasCompanion.insert(
          contentId: replica.contentId,
          nodeId: replica.nodeId,
          status: replica.state.wire,
          verified: Value(replica.verified),
          ciphertextHash: Value(replica.ciphertextHash),
          storedAt: Value(replica.storedAt),
          lastVerifiedAt: Value(replica.lastVerifiedAt),
          lastSeenAt: Value(replica.lastSeenAt),
        ),
      );

  @override
  Future<Set<String>> verifiedReplicaNodeIds(String contentId) async {
    final rows = await _db.replicasDao.forContent(contentId);
    return {
      for (final r in rows)
        if (r.verified) r.nodeId,
    };
  }

  @override
  Future<List<UploadJob>> unfinishedJobs() async {
    final rows = await _db.uploadJobsDao.unfinished();
    return [
      for (final r in rows)
        UploadJob(
          jobId: r.jobId,
          contentId: r.contentId,
          status: enumFromWire(UploadState.values, r.status),
          requestedReplicationFactor: r.requestedReplicationFactor,
          createdAt: r.createdAt.toUtc(),
          completedAt: r.completedAt?.toUtc(),
          failureReason: r.failureReason,
        ),
    ];
  }
}
