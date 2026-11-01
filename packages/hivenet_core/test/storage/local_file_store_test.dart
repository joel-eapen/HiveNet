import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late StorageLayout layout;
  late LocalFileStore store;

  const contentId = 'ab12cd34ef56';

  Uint8List bytesOf(int n) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 5 + 1) % 256));
  String hashOf(List<int> b) => crypto.sha256.convert(b).toString();

  File temp(String name, List<int> bytes) {
    final f = File('${layout.incompleteTransfersDir}/$name.part');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hn_store');
    layout = StorageLayout('${tmp.path}/HiveNet');
    for (final d in layout.allDirectories) {
      Directory(d).createSync(recursive: true);
    }
    store = LocalFileStore(layout, const Sha256IntegrityChecker());
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('commit', () {
    test('moves a verified file to its content-addressed path', () async {
      final data = bytesOf(5000);
      final t = temp('t1', data);
      await store.commit(
        temporaryPath: t.path,
        contentId: contentId,
        expectedCiphertextHash: hashOf(data),
      );
      final dest = File(layout.objectPath(contentId));
      expect(dest.path, endsWith('/objects/ab/$contentId.enc'));
      expect(dest.readAsBytesSync(), data);
      expect(t.existsSync(), isFalse, reason: 'temp file must be gone');
      expect(await store.exists(contentId), isTrue);
    });

    test('a hash mismatch commits nothing and removes the temp file', () async {
      final t = temp('t1', bytesOf(5000));
      await expectLater(
        store.commit(
          temporaryPath: t.path,
          contentId: contentId,
          expectedCiphertextHash: hashOf(bytesOf(10)),
        ),
        throwsA(isA<HiveError>()
            .having((e) => e.code, 'code', HiveErrorCode.integrityMismatch)),
      );
      expect(await store.exists(contentId), isFalse);
      expect(t.existsSync(), isFalse);
    });

    test('a bad commit does not damage an existing good object', () async {
      final good = bytesOf(2000);
      await store.commit(
        temporaryPath: temp('t1', good).path,
        contentId: contentId,
        expectedCiphertextHash: hashOf(good),
      );
      await expectLater(
        store.commit(
          temporaryPath: temp('t2', bytesOf(999)).path,
          contentId: contentId,
          expectedCiphertextHash: hashOf(good),
        ),
        throwsA(isA<HiveError>()),
      );
      expect(File(layout.objectPath(contentId)).readAsBytesSync(), good);
    });

    test('accepts an upper-case expected hash', () async {
      final data = bytesOf(100);
      await store.commit(
        temporaryPath: temp('t1', data).path,
        contentId: contentId,
        expectedCiphertextHash: hashOf(data).toUpperCase(),
      );
      expect(await store.exists(contentId), isTrue);
    });

    test('committing the same object again is safe', () async {
      final data = bytesOf(100);
      for (final name in ['t1', 't2']) {
        await store.commit(
          temporaryPath: temp(name, data).path,
          contentId: contentId,
          expectedCiphertextHash: hashOf(data),
        );
      }
      expect(File(layout.objectPath(contentId)).readAsBytesSync(), data);
    });

    test('rejects path-traversal content ids', () async {
      final data = bytesOf(10);
      await expectLater(
        store.commit(
          temporaryPath: temp('t1', data).path,
          contentId: '../../escape',
          expectedCiphertextHash: hashOf(data),
        ),
        throwsArgumentError,
      );
    });

    test('rejects temporary paths outside the incomplete-transfers dir',
        () async {
      final outside = File('${tmp.path}/outside.bin')..writeAsBytesSync([1, 2]);
      await expectLater(
        store.commit(
          temporaryPath: outside.path,
          contentId: contentId,
          expectedCiphertextHash: hashOf([1, 2]),
        ),
        throwsArgumentError,
      );
      // A ../ trick that normalises out of the directory.
      await expectLater(
        store.commit(
          temporaryPath: '${layout.incompleteTransfersDir}/../../outside.bin',
          contentId: contentId,
          expectedCiphertextHash: hashOf([1, 2]),
        ),
        throwsArgumentError,
      );
      expect(outside.existsSync(), isTrue, reason: 'must not be touched');
    });

    test('a missing temp file fails loudly', () {
      expect(
        store.commit(
          temporaryPath: '${layout.incompleteTransfersDir}/ghost.part',
          contentId: contentId,
          expectedCiphertextHash: hashOf([1]),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('reading and housekeeping', () {
    Future<void> put(String id, List<int> data) => store.commit(
          temporaryPath: temp('t-$id', data).path,
          contentId: id,
          expectedCiphertextHash: hashOf(data),
        );

    test('openRead streams the object, honouring start', () async {
      final data = bytesOf(3000);
      await put(contentId, data);
      Future<List<int>> read([int start = 0]) async => [
            for (final c in await store.openRead(contentId, start: start).toList()) ...c
          ];
      expect(await read(), data);
      expect(await read(1000), data.sublist(1000));
    });

    test('exists is false for unknown ids; delete is idempotent', () async {
      expect(await store.exists('ffffffffffff'), isFalse);
      await put(contentId, bytesOf(10));
      await store.delete(contentId);
      await store.delete(contentId);
      expect(await store.exists(contentId), isFalse);
    });

    test('usedBytes counts only committed objects', () async {
      expect(await store.usedBytes(), 0);
      await put('aa11bb22cc', bytesOf(1000));
      await put('bb22cc33dd', bytesOf(2500));
      temp('still-uploading', bytesOf(9999));
      File(layout.thumbnailPath('aa11bb22cc')).writeAsBytesSync(bytesOf(7777));
      expect(await store.usedBytes(), 3500);
      await store.delete('aa11bb22cc');
      expect(await store.usedBytes(), 2500);
    });

    test('unsafe ids are rejected by every operation', () {
      expect(() => store.exists('../x'), throwsArgumentError);
      expect(() => store.openRead('../x'), throwsArgumentError);
      expect(() => store.delete('../x'), throwsArgumentError);
    });
  });
}
