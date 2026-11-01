import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/image_files.dart';

part 'files_dao.g.dart';

@DriftAccessor(tables: [ImageFiles])
class FilesDao extends DatabaseAccessor<AppDatabase> with _$FilesDaoMixin {
  FilesDao(super.db);

  Future<List<ImageFileRow>> getAll() => select(imageFiles).get();

  Stream<List<ImageFileRow>> watchAll() => select(imageFiles).watch();

  Future<void> upsert(Insertable<ImageFileRow> row) =>
      into(imageFiles).insertOnConflictUpdate(row);

  Future<ImageFileRow?> byContentId(String contentId) => (select(imageFiles)
        ..where((t) => t.contentId.equals(contentId)))
      .getSingleOrNull();
}
