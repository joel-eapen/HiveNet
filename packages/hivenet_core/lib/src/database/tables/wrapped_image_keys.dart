import 'package:drift/drift.dart';

/// PRD §6.9. Stores only keys wrapped for one recipient; never plaintext keys.
@DataClassName('WrappedImageKeyRow')
class WrappedImageKeys extends Table {
  TextColumn get contentId => text()();
  TextColumn get recipientNodeId => text()();
  TextColumn get wrappedKey => text()();
  IntColumn get keyVersion => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {contentId, recipientNodeId, keyVersion};
}
