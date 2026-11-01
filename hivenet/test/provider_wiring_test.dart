import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivenet/adapters/app_paths.dart';
import 'package:hivenet/app/providers.dart';
import 'package:hivenet_core/hivenet_core.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('hn_wiring');
    final paths = await AppPaths.ensure('${tmp.path}/HiveNet');
    container = ProviderContainer(
      overrides: [appPathsProvider.overrideWithValue(paths)],
    );
  });
  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('Milestone 3 services are the real implementations', () {
    expect(container.read(encryptionServiceProvider), isA<AesGcmEncryptionService>());
    expect(container.read(integrityCheckerProvider), isA<Sha256IntegrityChecker>());
    expect(container.read(messageFramingProvider), isA<LengthPrefixedFraming>());
    expect(container.read(chunkManagerProvider), isA<FileChunkManager>());
    expect(container.read(fileStoreProvider), isA<LocalFileStore>());
  });

  test('the chunk size comes from the network config (1 MiB)', () {
    final chunks = container.read(chunkManagerProvider) as FileChunkManager;
    expect(chunks.chunkSize, 1024 * 1024);
  });

  test('the wired services work together against the app layout', () async {
    final enc = container.read(encryptionServiceProvider);
    final store = container.read(fileStoreProvider);
    final chunks = container.read(chunkManagerProvider);
    final integrity = container.read(integrityCheckerProvider);

    final data = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    final contentId = await integrity.sha256OfBytes(data);
    final obj = await enc.encrypt(data);

    await chunks.writeChunk(
        't1', Chunk(index: 0, bytes: obj.ciphertext, isLast: true));
    await store.commit(
      temporaryPath: chunks.pathFor('t1'),
      contentId: contentId,
      expectedCiphertextHash: obj.ciphertextHash,
    );
    expect(await store.exists(contentId), isTrue);
  });
}
