import 'package:drift/drift.dart';

/// PRD §6.4 and §13.1. Persisted so process death cannot create false success.
@DataClassName('UploadJobRow')
class UploadJobs extends Table {
  TextColumn get jobId => text()();
  TextColumn get contentId => text().nullable()();
  TextColumn get status => text()();
  IntColumn get requestedReplicationFactor => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get failureReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {jobId};
}
