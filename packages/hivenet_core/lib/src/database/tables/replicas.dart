import 'package:drift/drift.dart';

/// PRD §6.3. A record is a believed location, not proof of being online.
@DataClassName('ReplicaRow')
class Replicas extends Table {
  TextColumn get contentId => text()();
  TextColumn get nodeId => text()();
  TextColumn get status => text()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  TextColumn get ciphertextHash => text().nullable()();
  DateTimeColumn get storedAt => dateTime().nullable()();
  DateTimeColumn get lastVerifiedAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {contentId, nodeId};
}
