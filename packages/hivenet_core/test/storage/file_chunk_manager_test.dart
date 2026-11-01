import 'dart:io';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

void main() {
  const size = 1000; // small chunks keep the tests fast
  late Directory tmp;
  late StorageLayout layout;
  late FileChunkManager chunks;

  Uint8List bytesOf(int n, [int seed = 1]) =>
      Uint8List.fromList(List.generate(n, (i) => (i * seed + 3) % 256));

  File makeSource(int length) =>
      File('${tmp.path}/source.bin')..writeAsBytesSync(bytesOf(length));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('hn_chunks');
    layout = StorageLayout('${tmp.path}/HiveNet');
    for (final d in layout.allDirectories) {
      Directory(d).createSync(recursive: true);
    }
    chunks = FileChunkManager(layout, chunkSize: size);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('readChunks', () {
    test('splits a file and flags only the last chunk', () async {
      final src = makeSource(2500);
      final out = await chunks.readChunks(src.path).toList();
      expect(out.map((c) => c.index), [0, 1, 2]);
      expect(out.map((c) => c.bytes.length), [1000, 1000, 500]);
      expect(out.map((c) => c.isLast), [false, false, true]);
    });

    test('an exact multiple has a full-size last chunk', () async {
      final out = await chunks.readChunks(makeSource(2000).path).toList();
      expect(out.map((c) => c.bytes.length), [1000, 1000]);
      expect(out.last.isLast, isTrue);
    });

    test('startIndex resumes in the middle', () async {
      final src = makeSource(2500);
      final out = await chunks.readChunks(src.path, startIndex: 1).toList();
      expect(out.map((c) => c.index), [1, 2]);
      expect(out.first.bytes, src.readAsBytesSync().sublist(1000, 2000));
    });

    test('startIndex past the end yields nothing', () async {
      expect(await chunks.readChunks(makeSource(500).path, startIndex: 5).toList(),
          isEmpty);
    });

    test('an empty file yields no chunks', () async {
      expect(await chunks.readChunks(makeSource(0).path).toList(), isEmpty);
    });
  });

  group('writeChunk', () {
    test('reassembles exactly the original bytes', () async {
      final src = makeSource(2500);
      await for (final c in chunks.readChunks(src.path)) {
        await chunks.writeChunk('t1', c);
      }
      expect(File(chunks.pathFor('t1')).readAsBytesSync(), src.readAsBytesSync());
    });

    test('partial data lives only in the temporary directory', () async {
      await chunks.writeChunk('t1', Chunk(index: 0, bytes: bytesOf(size)));
      expect(chunks.pathFor('t1'), startsWith(layout.incompleteTransfersDir));
      expect(Directory(layout.objectsDir).listSync(recursive: true), isEmpty);
    });

    test('rejects a gap', () async {
      await chunks.writeChunk('t1', Chunk(index: 0, bytes: bytesOf(size)));
      expect(
        () => chunks.writeChunk('t1', Chunk(index: 2, bytes: bytesOf(size))),
        throwsStateError,
      );
    });

    test('rejects the first chunk arriving as index 1', () {
      expect(
        () => chunks.writeChunk('t1', Chunk(index: 1, bytes: bytesOf(size))),
        throwsStateError,
      );
    });

    test('rejects oversized and short non-final chunks', () async {
      expect(
        () => chunks.writeChunk('t1', Chunk(index: 0, bytes: bytesOf(size + 1))),
        throwsArgumentError,
      );
      expect(
        () => chunks.writeChunk('t1', Chunk(index: 0, bytes: bytesOf(10))),
        throwsArgumentError,
      );
    });

    test('accepts a short chunk when it is the last one', () async {
      await chunks.writeChunk(
          't1', Chunk(index: 0, bytes: bytesOf(10), isLast: true));
      expect(File(chunks.pathFor('t1')).lengthSync(), 10);
    });

    test('rejects data after a short last chunk', () async {
      await chunks.writeChunk(
          't1', Chunk(index: 0, bytes: bytesOf(10), isLast: true));
      expect(
        () => chunks.writeChunk('t1', Chunk(index: 1, bytes: bytesOf(size))),
        throwsStateError,
      );
    });

    test('re-sending an earlier chunk is idempotent', () async {
      final src = makeSource(2500);
      final all = await chunks.readChunks(src.path).toList();
      await chunks.writeChunk('t1', all[0]);
      await chunks.writeChunk('t1', all[1]);
      await chunks.writeChunk('t1', all[1]); // retry after a lost ack
      await chunks.writeChunk('t1', all[0]); // even further back
      await chunks.writeChunk('t1', all[1]);
      await chunks.writeChunk('t1', all[2]);
      expect(File(chunks.pathFor('t1')).readAsBytesSync(), src.readAsBytesSync());
    });
  });

  group('resume', () {
    test('nextExpectedIndex is 0 for an unknown transfer', () async {
      expect(await chunks.nextExpectedIndex('nope'), 0);
    });

    test('a fresh instance picks up where a previous one stopped', () async {
      final src = makeSource(3500);
      final all = await chunks.readChunks(src.path).toList();
      await chunks.writeChunk('t1', all[0]);
      await chunks.writeChunk('t1', all[1]);

      // Simulates an app restart: new object, same files on disk.
      final restarted = FileChunkManager(layout, chunkSize: size);
      expect(await restarted.nextExpectedIndex('t1'), 2);
      await for (final c in chunks.readChunks(src.path, startIndex: 2)) {
        await restarted.writeChunk('t1', c);
      }
      expect(File(restarted.pathFor('t1')).readAsBytesSync(), src.readAsBytesSync());
    });

    test('a half-written chunk after a crash is overwritten', () async {
      final src = makeSource(3000);
      final all = await chunks.readChunks(src.path).toList();
      await chunks.writeChunk('t1', all[0]);
      // Crash mid-write: 400 stray bytes of chunk 1 reached the disk.
      File(chunks.pathFor('t1'))
          .writeAsBytesSync(all[1].bytes.sublist(0, 400), mode: FileMode.append);
      expect(await chunks.nextExpectedIndex('t1'), 1);
      await chunks.writeChunk('t1', all[1]);
      await chunks.writeChunk('t1', all[2]);
      expect(File(chunks.pathFor('t1')).readAsBytesSync(), src.readAsBytesSync());
    });

    test('discard removes the partial file and is safe to repeat', () async {
      await chunks.writeChunk('t1', Chunk(index: 0, bytes: bytesOf(size)));
      await chunks.discard('t1');
      expect(File(chunks.pathFor('t1')).existsSync(), isFalse);
      expect(await chunks.nextExpectedIndex('t1'), 0);
      await chunks.discard('t1');
    });

    test('unsafe transfer ids are rejected', () {
      expect(() => chunks.pathFor('../evil'), throwsArgumentError);
    });
  });
}
