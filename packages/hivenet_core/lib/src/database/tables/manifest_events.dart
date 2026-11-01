import 'package:drift/drift.dart';

/// PRD §6.10. Ordered by per-owner `manifestVersion`, not wall-clock time.
@DataClassName('ManifestEventRow')
class ManifestEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get contentId => text()();
  TextColumn get originNodeId => text()();
  IntColumn get manifestVersion => integer()();
  TextColumn get eventType => text()();

  /// JSON payload.
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get signature => text().nullable()();

  @override
  Set<Column> get primaryKey => {eventId};

  @override
  List<Set<Column>> get uniqueKeys => [
        {originNodeId, contentId, manifestVersion},
      ];
}
