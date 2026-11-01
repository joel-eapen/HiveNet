import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/replicas.dart';

part 'replicas_dao.g.dart';

@DriftAccessor(tables: [Replicas])
class ReplicasDao extends DatabaseAccessor<AppDatabase> with _$ReplicasDaoMixin {
  ReplicasDao(super.db);

  Future<List<ReplicaRow>> getAll() => select(replicas).get();

  Stream<List<ReplicaRow>> watchAll() => select(replicas).watch();

  Future<void> upsert(Insertable<ReplicaRow> row) =>
      into(replicas).insertOnConflictUpdate(row);

  Future<List<ReplicaRow>> forContent(String contentId) =>
      (select(replicas)..where((t) => t.contentId.equals(contentId))).get();

  /// Replicas that count toward the replication factor (verified only).
  Future<int> verifiedCount(String contentId) async {
    final rows = await (select(replicas)
          ..where((t) => t.contentId.equals(contentId) & t.verified.equals(true)))
        .get();
    return rows.length;
  }
}
