import 'package:drift/drift.dart';

/// PRD §6.7 and §13.3. Owner-signed, device-bound; one row per permission.
@DataClassName('AccessGrantRow')
class AccessGrants extends Table {
  TextColumn get contentId => text()();
  TextColumn get granteeNodeId => text()();
  TextColumn get permission => text()();
  TextColumn get grantedBy => text()();
  IntColumn get grantVersion => integer()();
  IntColumn get keyVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();
  TextColumn get signature => text().nullable()();

  @override
  Set<Column> get primaryKey => {contentId, granteeNodeId, permission};
}
