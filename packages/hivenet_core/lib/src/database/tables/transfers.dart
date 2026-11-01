import 'package:drift/drift.dart';

/// PRD §6.5.
@DataClassName('TransferRow')
class Transfers extends Table {
  TextColumn get transferId => text()();
  TextColumn get contentId => text()();
  TextColumn get sourceNodeId => text()();
  TextColumn get destinationNodeId => text()();
  TextColumn get direction => text()();
  TextColumn get status => text()();
  IntColumn get bytesTransferred => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {transferId};
}
