import 'package:drift/drift.dart';

/// PRD §6.6. Holds the peer's public key only.
@DataClassName('TrustedDeviceRow')
class TrustedDevices extends Table {
  TextColumn get nodeId => text()();
  TextColumn get publicKey => text()();
  TextColumn get fingerprint => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get pairedAt => dateTime()();
  DateTimeColumn get revokedAt => dateTime().nullable()();
  TextColumn get trustStatus => text()();

  @override
  Set<Column> get primaryKey => {nodeId};
}
