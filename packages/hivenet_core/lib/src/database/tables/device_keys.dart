import 'package:drift/drift.dart';

/// PRD §6.8. Public keys only; private keys live in platform secure storage.
@DataClassName('DeviceKeyRow')
class DeviceKeys extends Table {
  TextColumn get nodeId => text()();
  TextColumn get publicKey => text()();
  TextColumn get keyAlgorithm => text()();
  TextColumn get fingerprint => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get rotatedAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {nodeId, fingerprint};
}
