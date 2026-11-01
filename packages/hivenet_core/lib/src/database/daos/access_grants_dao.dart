import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/access_grants.dart';

part 'access_grants_dao.g.dart';

@DriftAccessor(tables: [AccessGrants])
class AccessGrantsDao extends DatabaseAccessor<AppDatabase> with _$AccessGrantsDaoMixin {
  AccessGrantsDao(super.db);

  Future<List<AccessGrantRow>> getAll() => select(accessGrants).get();

  Stream<List<AccessGrantRow>> watchAll() => select(accessGrants).watch();

  Future<void> upsert(Insertable<AccessGrantRow> row) =>
      into(accessGrants).insertOnConflictUpdate(row);

  Future<List<AccessGrantRow>> forContent(String contentId) =>
      (select(accessGrants)..where((t) => t.contentId.equals(contentId))).get();
}
