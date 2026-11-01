import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

/// End-to-end check of the Milestone 3 foundation, using only the real classes:
///
/// contentId -> encrypt -> chunk -> frame -> (wire) -> decode -> reassemble
///   -> verify ciphertext hash -> atomic commit -> read back -> decrypt
///   -> verify contentId
void main() {
  const checker = Sha256IntegrityChecker();
  final encryption = AesGcmEncryptionService();
  final framing = LengthPrefixedFraming();
  const chunkSize = 1024 * 1024;

  late Directory tmp;
  late StorageLayout senderLayout;
  late StorageLayout receiverLayout;

  // A stand-in for a compressed image (about 2.6 MiB, so three chunks).
  final plaintext = Uint8List.fromList(
    List.generate(2 * 1024 * 1024 + 600000, (i) => (i * 31 + (i >> 8)) % 256),
  );

  StorageLayout makeLayout(String name) {
    final layout = StorageLayout('${tmp.path}/$name');
    for (final d in layout.allDirectories) {
      Directory(d).createSync(recursive: true);
    }
    return layout;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hn_pipeline');
    senderLayout = makeLayout('sender');
    receiverLayout = makeLayout('receiver');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Sender side: prepare the encrypted object on disk and return its facts.
  Future<({String contentId, EncryptedObject object, String path})> prepare() async {
    final contentId = await checker.sha256OfBytes(plaintext);
    final object = await encryption.encrypt(plaintext);
    final path = '${senderLayout.rootPath}/outgoing.enc';
    File(path).writeAsBytesSync(object.ciphertext);
    return (contentId: contentId, object: object, path: path);
  }

  /// Sends chunks [fromIndex]..end as framed bytes, as one byte buffer.
  Future<Uint8List> frameChunks(
      String path, String contentId, FileChunkManager sender,
      {int fromIndex = 0, int? stopAfter}) async {
    final wire = BytesBuilder();
    var sent = 0;
    await for (final c in sender.readChunks(path, startIndex: fromIndex)) {
      wire.add(framing.encode(MessageEnvelope(
        type: MessageType.chunkData,
        requestId: 'req-1',
        senderNodeId: 'node-a',
        contentId: contentId,
        payload: {'index': c.index, 'last': c.isLast},
        data: c.bytes,
      )));
      if (stopAfter != null && ++sent >= stopAfter) break;
    }
    return wire.toBytes();
  }

  /// Receiver side: decode arbitrary read sizes and write every chunk.
  Future<void> receive(Uint8List wire, FileChunkManager receiver,
      {int seed = 7}) async {
    final decoder = FrameDecoder(maxFrameBytes: 4 * 1024 * 1024);
    final rnd = Random(seed);
    var i = 0;
    while (i < wire.length) {
      final n = min(1 + rnd.nextInt(200000), wire.length - i);
      for (final m in decoder.add(wire.sublist(i, i + n))) {
        await receiver.writeChunk(
          'transfer-1',
          Chunk(
            index: m.payload['index']! as int,
            bytes: m.data!,
            isLast: m.payload['last']! as bool,
          ),
        );
      }
      i += n;
    }
    decoder.close();
  }

  test('an image survives the whole pipeline and decrypts to the original',
      () async {
    final p = await prepare();
    final sender = FileChunkManager(senderLayout, chunkSize: chunkSize);
    final receiver = FileChunkManager(receiverLayout, chunkSize: chunkSize);
    final store = LocalFileStore(receiverLayout, checker);

    await receive(await frameChunks(p.path, p.contentId, sender), receiver);

    // Nothing is a replica until the commit.
    expect(await store.exists(p.contentId), isFalse);

    await store.commit(
      temporaryPath: receiver.pathFor('transfer-1'),
      contentId: p.contentId,
      expectedCiphertextHash: p.object.ciphertextHash,
    );
    expect(await store.exists(p.contentId), isTrue);

    // Read back from the object store, decrypt, check the content id.
    final stored = BytesBuilder();
    await for (final c in store.openRead(p.contentId)) {
      stored.add(c);
    }
    final clear = await encryption.decrypt(
      ciphertext: stored.toBytes(),
      imageKey: p.object.imageKey,
    );
    expect(clear, plaintext);
    expect(await checker.sha256OfBytes(clear), p.contentId);
  });

  test('a byte corrupted in transit is caught and nothing is committed',
      () async {
    final p = await prepare();
    final sender = FileChunkManager(senderLayout, chunkSize: chunkSize);
    final receiver = FileChunkManager(receiverLayout, chunkSize: chunkSize);
    final store = LocalFileStore(receiverLayout, checker);

    final wire = await frameChunks(p.path, p.contentId, sender);
    wire[wire.length ~/ 2] ^= 0x01; // flip one bit mid-stream
    await receive(wire, receiver);

    await expectLater(
      store.commit(
        temporaryPath: receiver.pathFor('transfer-1'),
        contentId: p.contentId,
        expectedCiphertextHash: p.object.ciphertextHash,
      ),
      throwsA(isA<HiveError>()
          .having((e) => e.code, 'code', HiveErrorCode.integrityMismatch)),
    );
    expect(await store.exists(p.contentId), isFalse);
    expect(File(receiver.pathFor('transfer-1')).existsSync(), isFalse);
    expect(await store.usedBytes(), 0);
  });

  test('a replica committed with the wrong key material still cannot be opened',
      () async {
    final p = await prepare();
    final sender = FileChunkManager(senderLayout, chunkSize: chunkSize);
    final receiver = FileChunkManager(receiverLayout, chunkSize: chunkSize);
    final store = LocalFileStore(receiverLayout, checker);

    await receive(await frameChunks(p.path, p.contentId, sender), receiver);
    await store.commit(
      temporaryPath: receiver.pathFor('transfer-1'),
      contentId: p.contentId,
      expectedCiphertextHash: p.object.ciphertextHash,
    );

    // A storage peer holds the object but not the key, so it cannot read it.
    final stored = await File(receiverLayout.objectPath(p.contentId)).readAsBytes();
    await expectLater(
      encryption.decrypt(ciphertext: stored, imageKey: Uint8List(32)),
      throwsA(isA<HiveError>()),
    );
  });

  test('an interrupted transfer resumes after a restart and still verifies',
      () async {
    final p = await prepare();
    final sender = FileChunkManager(senderLayout, chunkSize: chunkSize);
    var receiver = FileChunkManager(receiverLayout, chunkSize: chunkSize);

    // First connection delivers only two chunks, then drops.
    await receive(
      await frameChunks(p.path, p.contentId, sender, stopAfter: 2),
      receiver,
    );
    expect(await receiver.nextExpectedIndex('transfer-1'), 2);

    // The app restarts: all in-memory state is gone, files remain.
    receiver = FileChunkManager(receiverLayout, chunkSize: chunkSize);
    final resumeAt = await receiver.nextExpectedIndex('transfer-1');
    expect(resumeAt, 2);

    await receive(
      await frameChunks(p.path, p.contentId, sender, fromIndex: resumeAt),
      receiver,
    );

    final store = LocalFileStore(receiverLayout, checker);
    await store.commit(
      temporaryPath: receiver.pathFor('transfer-1'),
      contentId: p.contentId,
      expectedCiphertextHash: p.object.ciphertextHash,
    );
    final clear = await encryption.decrypt(
      ciphertext: await File(receiverLayout.objectPath(p.contentId)).readAsBytes(),
      imageKey: p.object.imageKey,
    );
    expect(await checker.sha256OfBytes(clear), p.contentId);
  });

  test('the same flow works for a tiny object that fits in one chunk', () async {
    final tiny = Uint8List.fromList([1, 2, 3, 4, 5]);
    final contentId = await checker.sha256OfBytes(tiny);
    final object = await encryption.encrypt(tiny);
    final path = '${senderLayout.rootPath}/tiny.enc';
    File(path).writeAsBytesSync(object.ciphertext);

    final sender = FileChunkManager(senderLayout, chunkSize: chunkSize);
    final receiver = FileChunkManager(receiverLayout, chunkSize: chunkSize);
    final store = LocalFileStore(receiverLayout, checker);
    await receive(await frameChunks(path, contentId, sender), receiver);
    await store.commit(
      temporaryPath: receiver.pathFor('transfer-1'),
      contentId: contentId,
      expectedCiphertextHash: object.ciphertextHash,
    );
    final clear = await encryption.decrypt(
      ciphertext: await File(receiverLayout.objectPath(contentId)).readAsBytes(),
      imageKey: object.imageKey,
    );
    expect(clear, tiny);
  });
}
