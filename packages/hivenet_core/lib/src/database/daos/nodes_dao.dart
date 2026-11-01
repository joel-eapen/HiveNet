import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/nodes.dart';

part 'nodes_dao.g.dart';

@DriftAccessor(tables: [Nodes])
class NodesDao extends DatabaseAccessor<AppDatabase> with _$NodesDaoMixin {
  NodesDao(super.db);

  Future<List<NodeRow>> getAll() => select(nodes).get();

  Stream<List<NodeRow>> watchAll() => select(nodes).watch();

  Future<void> upsert(Insertable<NodeRow> row) =>
      into(nodes).insertOnConflictUpdate(row);

  Future<NodeRow?> byId(String nodeId) =>
      (select(nodes)..where((t) => t.nodeId.equals(nodeId))).getSingleOrNull();
}
