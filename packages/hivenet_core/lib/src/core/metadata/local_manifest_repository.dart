import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../shared/models/enums.dart';
import '../../shared/models/image_manifest.dart';

/// Reads and writes this device's view of the gallery (PRD FR-07).
///
/// This is local storage only: it holds manifests this device created or
/// learned about. Syncing them with other devices, and signing them, is the
/// separate manifest-sync work.
class LocalManifestRepository {
  LocalManifestRepository(this._db);

  final AppDatabase _db;

  Future<void> save(ImageManifest m) => _db.filesDao.upsert(ImageFilesCompanion.insert(
        contentId: m.contentId,
        ownerNodeId: m.ownerNodeId,
        fileName: m.fileName,
        mimeType: m.mimeType,
        fileSizeBytes: m.fileSizeBytes,
        width: m.width,
        height: m.height,
        importance: m.importance.wire,
        visibility: m.visibility.wire,
        desiredReplicationFactor: m.desiredReplicationFactor,
        createdAt: m.createdAt,
        manifestVersion: m.manifestVersion,
        availabilityStatus: m.availabilityStatus.wire,
        thumbnailReference: Value(m.thumbnailReference),
        ciphertextHash: Value(m.ciphertextHash),
        encryptionMetadata: Value(jsonEncode(m.encryptionMetadata)),
      ));

  Future<ImageManifest?> byId(String contentId) async {
    final row = await _db.filesDao.byContentId(contentId);
    return row == null ? null : _toModel(row);
  }

  Future<List<ImageManifest>> all() async {
    final rows = await _db.filesDao.getAll();
    return _sorted(rows);
  }

  Stream<List<ImageManifest>> watchAll() =>
      _db.filesDao.watchAll().map(_sorted);

  Future<void> setAvailability(String contentId, AvailabilityStatus status) async {
    final current = await byId(contentId);
    if (current == null) return;
    await save(ImageManifest(
      contentId: current.contentId,
      ownerNodeId: current.ownerNodeId,
      fileName: current.fileName,
      mimeType: current.mimeType,
      fileSizeBytes: current.fileSizeBytes,
      width: current.width,
      height: current.height,
      importance: current.importance,
      visibility: current.visibility,
      desiredReplicationFactor: current.desiredReplicationFactor,
      createdAt: current.createdAt,
      manifestVersion: current.manifestVersion + 1,
      availabilityStatus: status,
      thumbnailReference: current.thumbnailReference,
      ciphertextHash: current.ciphertextHash,
      encryptionMetadata: current.encryptionMetadata,
    ));
  }

  List<ImageManifest> _sorted(List<ImageFileRow> rows) =>
      [for (final r in rows) _toModel(r)]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  ImageManifest _toModel(ImageFileRow r) => ImageManifest(
        contentId: r.contentId,
        ownerNodeId: r.ownerNodeId,
        fileName: r.fileName,
        mimeType: r.mimeType,
        fileSizeBytes: r.fileSizeBytes,
        width: r.width,
        height: r.height,
        importance: enumFromWire(Importance.values, r.importance),
        visibility: enumFromWire(ImageVisibility.values, r.visibility),
        desiredReplicationFactor: r.desiredReplicationFactor,
        createdAt: r.createdAt.toUtc(),
        manifestVersion: r.manifestVersion,
        availabilityStatus:
            enumFromWire(AvailabilityStatus.values, r.availabilityStatus),
        thumbnailReference: r.thumbnailReference,
        ciphertextHash: r.ciphertextHash,
        encryptionMetadata:
            Map<String, Object?>.from(jsonDecode(r.encryptionMetadata) as Map),
      );
}
