import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/upload_jobs.dart';

part 'upload_jobs_dao.g.dart';

@DriftAccessor(tables: [UploadJobs])
class UploadJobsDao extends DatabaseAccessor<AppDatabase> with _$UploadJobsDaoMixin {
  UploadJobsDao(super.db);

  Future<List<UploadJobRow>> getAll() => select(uploadJobs).get();

  Stream<List<UploadJobRow>> watchAll() => select(uploadJobs).watch();

  Future<void> upsert(Insertable<UploadJobRow> row) =>
      into(uploadJobs).insertOnConflictUpdate(row);

  Future<UploadJobRow?> byId(String jobId) =>
      (select(uploadJobs)..where((t) => t.jobId.equals(jobId))).getSingleOrNull();

  /// Jobs to resume after a restart (anything not in a terminal state).
  Future<List<UploadJobRow>> unfinished() => (select(uploadJobs)
        ..where((t) => t.status.isNotIn(['COMPLETED', 'FAILED'])))
      .get();
}
