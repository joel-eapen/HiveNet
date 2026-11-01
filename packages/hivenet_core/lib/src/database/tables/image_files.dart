import 'package:drift/drift.dart';

/// PRD §6.2. Manifest metadata only; no image bytes, no key material.
@DataClassName('ImageFileRow')
class ImageFiles extends Table {
  TextColumn get contentId => text()();
  TextColumn get ownerNodeId => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get fileSizeBytes => integer()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  TextColumn get thumbnailReference => text().nullable()();
  TextColumn get importance => text()();
  TextColumn get visibility => text()();
  IntColumn get desiredReplicationFactor => integer()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get manifestVersion => integer()();
  TextColumn get availabilityStatus => text()();
  TextColumn get ciphertextHash => text().nullable()();

  /// JSON of non-secret encryption parameters (cipher, nonce).
  TextColumn get encryptionMetadata =>
      text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {contentId};
}
