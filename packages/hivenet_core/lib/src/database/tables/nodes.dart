import 'package:drift/drift.dart';

/// PRD §6.1. Telemetry is an estimate, not proof of capacity.
@DataClassName('NodeRow')
class Nodes extends Table {
  TextColumn get nodeId => text()();
  TextColumn get deviceName => text()();
  TextColumn get platform => text()();

  /// JSON-encoded list of addresses.
  TextColumn get ipAddresses => text().withDefault(const Constant('[]'))();
  IntColumn get port => integer()();
  IntColumn get protocolVersion => integer()();
  IntColumn get totalStorageBytes => integer().withDefault(const Constant(0))();
  IntColumn get availableStorageBytes =>
      integer().withDefault(const Constant(0))();
  IntColumn get reservedStorageBytes =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSeen => dateTime().nullable()();
  TextColumn get status => text()();
  IntColumn get latencyMs => integer().nullable()();
  IntColumn get bandwidthEstimate => integer().nullable()();
  RealColumn get reliabilityScore => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {nodeId};
}
