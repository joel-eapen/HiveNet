import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/transfers.dart';

part 'transfers_dao.g.dart';

@DriftAccessor(tables: [Transfers])
class TransfersDao extends DatabaseAccessor<AppDatabase> with _$TransfersDaoMixin {
  TransfersDao(super.db);

  Future<List<TransferRow>> getAll() => select(transfers).get();

  Stream<List<TransferRow>> watchAll() => select(transfers).watch();

  Future<void> upsert(Insertable<TransferRow> row) =>
      into(transfers).insertOnConflictUpdate(row);

  Future<TransferRow?> byId(String transferId) => (select(transfers)
        ..where((t) => t.transferId.equals(transferId)))
      .getSingleOrNull();
}
