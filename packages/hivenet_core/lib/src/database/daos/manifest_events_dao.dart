import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/manifest_events.dart';

part 'manifest_events_dao.g.dart';

@DriftAccessor(tables: [ManifestEvents])
class ManifestEventsDao extends DatabaseAccessor<AppDatabase> with _$ManifestEventsDaoMixin {
  ManifestEventsDao(super.db);

  Future<List<ManifestEventRow>> getAll() => select(manifestEvents).get();

  Stream<List<ManifestEventRow>> watchAll() => select(manifestEvents).watch();

  Future<void> upsert(Insertable<ManifestEventRow> row) =>
      into(manifestEvents).insertOnConflictUpdate(row);

  Future<List<ManifestEventRow>> since(String originNodeId, int afterVersion) =>
      (select(manifestEvents)
            ..where((t) =>
                t.originNodeId.equals(originNodeId) &
                t.manifestVersion.isBiggerThanValue(afterVersion))
            ..orderBy([(t) => OrderingTerm.asc(t.manifestVersion)]))
          .get();
}
