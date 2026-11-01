import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivenet/adapters/app_paths.dart';
import 'package:hivenet_core/hivenet_core.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hivenet_paths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('creates every FR-10 directory', () async {
    final paths = await AppPaths.ensure('${tmp.path}/HiveNet');
    for (final dir in paths.layout.allDirectories) {
      expect(Directory(dir).existsSync(), isTrue, reason: dir);
    }
    expect(paths.layout.databasePath, endsWith('database/hivenet.sqlite'));
  });

  test('is idempotent', () async {
    await AppPaths.ensure('${tmp.path}/HiveNet');
    await AppPaths.ensure('${tmp.path}/HiveNet');
    expect(Directory('${tmp.path}/HiveNet/objects').existsSync(), isTrue);
  });

  test('uses the documented layout', () {
    const layout = StorageLayout('/x');
    expect(layout.objectPath('abcd'), '/x/objects/ab/abcd.enc');
  });
}
