import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/trusted_devices.dart';

part 'trusted_devices_dao.g.dart';

@DriftAccessor(tables: [TrustedDevices])
class TrustedDevicesDao extends DatabaseAccessor<AppDatabase> with _$TrustedDevicesDaoMixin {
  TrustedDevicesDao(super.db);

  Future<List<TrustedDeviceRow>> getAll() => select(trustedDevices).get();

  Stream<List<TrustedDeviceRow>> watchAll() => select(trustedDevices).watch();

  Future<void> upsert(Insertable<TrustedDeviceRow> row) =>
      into(trustedDevices).insertOnConflictUpdate(row);

  Future<TrustedDeviceRow?> byNodeId(String nodeId) => (select(trustedDevices)
        ..where((t) => t.nodeId.equals(nodeId)))
      .getSingleOrNull();
}
