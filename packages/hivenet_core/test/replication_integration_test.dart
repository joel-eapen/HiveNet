import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import 'helpers/fake_replication.dart';
import 'helpers/net.dart';
import 'helpers/peers.dart';

/// A storage peer: a real server, real files, real quota.
class StorageNode {
  StorageNode._(this.device, this.dir, this.layout, this.files, this.chunks,
      this.quota, this._uploader);

  final TestDevice device;
  final Directory dir;
  final StorageLayout layout;
  final LocalFileStore files;
  final FileChunkManager chunks;
  final LocalQuotaManager quota;
  final TestDevice _uploader;
  PeerServer? _server;
  int port = 0;

  static Future<StorageNode> start(
    TestDevice device,
    TestDevice uploader, {
    int quotaBytes = 100 * 1024 * 1024,
  }) async {
    final dir = Directory.systemTemp.createTempSync('hn_store_${device.nodeId.substring(5, 11)}');
    final layout = StorageLayout('${dir.path}/HiveNet');
    for (final d in layout.allDirectories) {
      Directory(d).createSync(recursive: true);
    }
    final files = LocalFileStore(layout, const Sha256IntegrityChecker());
    final node = StorageNode._(
      device, dir, layout, files, FileChunkManager(layout),
      LocalQuotaManager(
          quotaBytes: quotaBytes, storedBytes: files.usedBytes, safetyMarginBytes: 0),
      uploader,
    );
    await node.listen();
    return node;
  }

  /// (Re)starts the server. The port changes, like a phone rejoining.
  Future<void> listen() async {
    final service = PeerStorageService(files: files, chunks: chunks, quota: quota);
    _server = PeerServer(
      identity: device.identity,
      signer: device.service,
      verifier: verifierFor([_uploader]), // only the paired uploader
      onChannel: (c) => service.serve(c),
    );
    port = await _server!.start(address: InternetAddress.loopbackIPv4);
  }

  Future<void> stop() async => _server?.stop();

  bool has(String contentId) => File(layout.objectPath(contentId)).existsSync();
  Uint8List stored(String contentId) => File(layout.objectPath(contentId)).readAsBytesSync();
  int partialBytes(String jobId, TestDevice from) {
    final f = File(chunks.pathFor('${from.nodeId}_$jobId'));
    return f.existsSync() ? f.lengthSync() : 0;
  }

  Future<void> dispose() async {
    await stop();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  late TestDevice uploader;
  late TestDevice dev1;
  late TestDevice dev2;
  late StorageNode s1;
  late StorageNode s2;
  late Directory uploaderDir;
  late StorageLayout uploaderLayout;
  late EncryptedObject object;
  late Uint8List plaintext;
  late String contentId;
  late ReplicationSource source;
  late MemoryReplicationStore store;
  late Map<String, int> ports; // address book
  late DefaultReplicationManager manager;
  final dialed = <String>[];

  UploadJob newJob([String id = 'job-1']) => UploadJob(
        jobId: id,
        status: UploadState.created,
        requestedReplicationFactor: 2,
        createdAt: DateTime.utc(2026, 11, 1),
      );

  Future<PlacementPlan> planFor(List<StorageNode> nodes) =>
      DeterministicStorageRouter(
        trustedNodeIds: () async => {for (final n in nodes) n.device.nodeId},
        policy: const EligibilityPolicy(safetyMarginBytes: 0),
        clock: () => testNow,
      ).plan(
        PlacementRequest(sizeBytes: source.sizeBytes, importance: Importance.normal),
        [for (final n in nodes) peer(n.device.nodeId)],
      );

  Future<UploadJob> run(UploadJob job, PlacementPlan plan) async =>
      (await manager.replicate(job, plan, source).toList()).last;

  Future<SecureChannel> defaultDial(String nodeId) async {
    dialed.add(nodeId);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, ports[nodeId]!);
    return SecureChannel.connect(socket,
        identity: uploader.identity,
        signer: uploader.service,
        verifier: verifierFor([dev1, dev2]));
  }

  DefaultReplicationManager makeManager({DialPeer? dial}) => DefaultReplicationManager(
        store: store,
        transport: ChannelReplicaTransport(
          localNodeId: uploader.nodeId,
          chunks: FileChunkManager(uploaderLayout),
          dial: dial ?? defaultDial,
        ),
      );

  setUp(() async {
    uploader = await TestDevice.create('uploader');
    dev1 = await TestDevice.create('storage-1');
    dev2 = await TestDevice.create('storage-2');
    s1 = await StorageNode.start(dev1, uploader);
    s2 = await StorageNode.start(dev2, uploader);
    ports = {dev1.nodeId: s1.port, dev2.nodeId: s2.port};
    dialed.clear();

    uploaderDir = Directory.systemTemp.createTempSync('hn_uploader');
    uploaderLayout = StorageLayout('${uploaderDir.path}/HiveNet');
    for (final d in uploaderLayout.allDirectories) {
      Directory(d).createSync(recursive: true);
    }

    // A 2.6 MiB "compressed image": three chunks.
    plaintext = Uint8List.fromList(
        List.generate(2 * 1024 * 1024 + 600000, (i) => (i * 31 + (i >> 9)) % 256));
    contentId = await const Sha256IntegrityChecker().sha256OfBytes(plaintext);
    object = await AesGcmEncryptionService().encrypt(plaintext);
    final path = '${uploaderDir.path}/object.enc';
    File(path).writeAsBytesSync(object.ciphertext);
    source = ReplicationSource(
      contentId: contentId,
      objectPath: path,
      ciphertextHash: object.ciphertextHash,
      sizeBytes: object.ciphertext.length,
    );

    store = MemoryReplicationStore();
    manager = makeManager();
  });

  tearDown(() async {
    await s1.dispose();
    await s2.dispose();
    uploaderDir.deleteSync(recursive: true);
  });

  group('a normal upload', () {
    test('reaches two verified replicas on two distinct devices', () async {
      final plan = await planFor([s1, s2]);
      final job = await run(newJob(), plan);

      expect(job.status, UploadState.completed);
      expect(s1.has(contentId), isTrue);
      expect(s2.has(contentId), isTrue);
      expect(s1.stored(contentId), object.ciphertext);
      expect(s2.stored(contentId), object.ciphertext);
      expect(await store.verifiedReplicaNodeIds(contentId), {dev1.nodeId, dev2.nodeId});
    });

    test('storage peers hold ciphertext only, and cannot read it without the key', () async {
      await run(newJob(), await planFor([s1, s2]));
      final onDisk = s1.stored(contentId);

      expect(onDisk, isNot(contains(plaintext.sublist(1000, 1032))));
      final enc = AesGcmEncryptionService();
      // Without the key (or with a guess) it does not open.
      await expectLater(
          enc.decrypt(ciphertext: onDisk, imageKey: Uint8List(32)), throwsA(isA<HiveError>()));
      // With the key the owner holds, it decrypts to the original image.
      final clear = await enc.decrypt(ciphertext: onDisk, imageKey: object.imageKey);
      expect(clear, plaintext);
      expect(await const Sha256IntegrityChecker().sha256OfBytes(clear), contentId);
    });

    test('leaves no temporary files and releases the reservation', () async {
      await run(newJob(), await planFor([s1, s2]));
      for (final n in [s1, s2]) {
        expect(Directory(n.layout.incompleteTransfersDir).listSync(), isEmpty);
        expect(await n.quota.reservedBytes, 0);
        expect(await n.files.usedBytes(), object.ciphertext.length);
      }
    });

    test('uploading the same object again is harmless', () async {
      final plan = await planFor([s1, s2]);
      await run(newJob(), plan);
      store = MemoryReplicationStore(); // forget local state: peers still hold it
      manager = makeManager();
      final again = await run(newJob('job-2'), plan);
      expect(again.status, UploadState.completed);
      expect(s1.stored(contentId), object.ciphertext);
    });
  });

  group('when things go wrong', () {
    test('a storage peer with no room is skipped and the job says so', () async {
      await s2.dispose();
      s2 = await StorageNode.start(dev2, uploader, quotaBytes: 1024); // too small
      ports[dev2.nodeId] = s2.port;
      final job = await run(newJob(), await planFor([s1, s2]));

      expect(job.status, UploadState.underReplicated);
      expect(job.failureReason, contains('storage_full'));
      expect(s1.has(contentId), isTrue);
      expect(s2.has(contentId), isFalse);
      expect(await store.verifiedReplicaNodeIds(contentId), {dev1.nodeId});
    });

    test('a peer that is offline leaves the job under-replicated, and a retry finishes it', () async {
      final plan = await planFor([s1, s2]);
      await s2.stop();
      final first = await run(newJob(), plan);
      expect(first.status, UploadState.underReplicated);
      expect(s1.has(contentId), isTrue);
      expect(s2.has(contentId), isFalse);

      // The phone comes back (on a new port) and the job is retried.
      await s2.listen();
      ports[dev2.nodeId] = s2.port;
      dialed.clear();
      final retried = await run(first, plan);

      expect(retried.status, UploadState.completed);
      expect(s2.stored(contentId), object.ciphertext);
      expect(dialed, [dev2.nodeId], reason: 'only the missing replica is sent');
    });

    test('both peers offline: nothing is claimed, the job waits to retry', () async {
      await s1.stop();
      await s2.stop();
      final job = await run(newJob(), await planFor([s1, s2]));
      expect(job.status, UploadState.retryPending);
      expect(await store.verifiedReplicaNodeIds(contentId), isEmpty);
    });

    test('a connection cut mid-upload resumes where it stopped', () async {
      final plan = await planFor([s1, s2]);
      final mitm = await Mitm.start(s2.port);
      addTearDown(mitm.close);
      // Cut once about 1.5 MiB has gone out: after the first chunk, during the second.
      mitm.dropAfterClientBytes = (1.5 * 1024 * 1024).toInt();
      ports[dev2.nodeId] = mitm.port;

      final first = await run(newJob(), plan);
      expect(first.status, UploadState.underReplicated);
      expect(s2.has(contentId), isFalse, reason: 'not committed');
      final partial = s2.partialBytes('job-1', uploader);
      expect(partial, greaterThan(0), reason: 'the first chunk was kept');
      expect(partial, lessThan(object.ciphertext.length));

      // Network is back: connect straight to the peer and retry.
      ports[dev2.nodeId] = s2.port;
      final second = await run(first, plan);
      expect(second.status, UploadState.completed);
      expect(s2.stored(contentId), object.ciphertext);
    });

    test('data altered in transit is caught and never becomes a replica', () async {
      final plan = await planFor([s1, s2]);
      final mitm = await Mitm.start(s2.port);
      addTearDown(mitm.close);
      var flipped = false;
      mitm.tamperClientToServer = (d) {
        if (!flipped && d.length > 10000) {
          flipped = true;
          final copy = Uint8List.fromList(d);
          copy[5000] ^= 0x01;
          return copy;
        }
        return d;
      };
      ports[dev2.nodeId] = mitm.port;

      final job = await run(newJob(), plan);
      expect(flipped, isTrue);
      expect(job.status, UploadState.underReplicated);
      expect(s2.has(contentId), isFalse);
      expect(await store.verifiedReplicaNodeIds(contentId), {dev1.nodeId});
    });

    test('a different device answering at the expected address is not trusted', () async {
      final impostor = await TestDevice.create('impostor');
      final fake = await StorageNode.start(impostor, uploader);
      addTearDown(fake.dispose);
      ports[dev2.nodeId] = fake.port; // address now belongs to someone else

      final job = await run(newJob(), await planFor([s1, s2]));
      expect(job.status, UploadState.underReplicated);
      expect(fake.has(contentId), isFalse);
    });
  });

  group('who may store', () {
    test('a device that is not paired with the storage peer cannot upload to it', () async {
      final stranger = await TestDevice.create('stranger');
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, s1.port);
      await expectLater(
        SecureChannel.connect(socket,
            identity: stranger.identity,
            signer: stranger.service,
            verifier: verifierFor([dev1]),
            timeout: const Duration(seconds: 3)),
        throwsA(isA<HiveError>()),
      );
      expect(await s1.files.usedBytes(), 0);
    });

    test('a paired uploader cannot touch another uploader\'s partial upload', () async {
      // Reservations and partial files are keyed by the proven node id.
      await run(newJob('shared-id'), await planFor([s1, s2]));
      final other = await TestDevice.create('other-uploader');
      expect(s1.partialBytes('shared-id', other), 0);
    });
  });

  group('the storage service validates what it is sent', () {
    late SecureChannel channel;
    late StreamIterator<MessageEnvelope> inbox;

    setUp(() async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, s1.port);
      channel = await SecureChannel.connect(socket,
          identity: uploader.identity,
          signer: uploader.service,
          verifier: verifierFor([dev1]));
      // One listener for the whole test: the stream allows only one.
      inbox = StreamIterator(channel.messages);
    });
    tearDown(() async {
      await inbox.cancel();
      await channel.close();
    });

    Future<MessageEnvelope> ask(MessageType type, Map<String, Object?> payload,
        {String? contentId = 'abcdef12', Uint8List? data}) async {
      await channel.send(MessageEnvelope(
        type: type,
        requestId: 'r',
        senderNodeId: uploader.nodeId,
        contentId: contentId,
        payload: payload,
        data: data,
      ));
      expect(await inbox.moveNext().timeout(const Duration(seconds: 3)), isTrue);
      return inbox.current;
    }

    test('a path-traversal job id is refused', () async {
      final r = await ask(MessageType.storageReserve, {'jobId': '../../etc', 'size': 10});
      expect(r.type, MessageType.error);
    });

    test('a path-traversal content id is refused', () async {
      final r = await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': 10},
          contentId: '../../x');
      expect(r.type, MessageType.error);
    });

    test('a missing content id is refused', () async {
      final r = await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': 10}, contentId: null);
      expect(r.type, MessageType.error);
    });

    test('absurd sizes are rejected without reserving anything', () async {
      for (final size in [0, -5, 1 << 40]) {
        final r = await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': size});
        expect(r.type, MessageType.storageReject, reason: '$size');
      }
      expect(await s1.quota.reservedBytes, 0);
    });

    test('data cannot be sent without a reservation', () async {
      final r = await ask(MessageType.chunkData, {'jobId': 'j1', 'index': 0, 'last': true},
          data: Uint8List(10));
      expect(r.type, MessageType.error);
    });

    test('committing without uploading is refused and stores nothing', () async {
      expect((await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': 100})).type,
          MessageType.storageAccept);
      final r = await ask(MessageType.uploadCommit, {'jobId': 'j1', 'ciphertextHash': 'a' * 64});
      expect(r.type, MessageType.error);
      expect(s1.has('abcdef12'), isFalse);
    });

    test('more data than was reserved is refused', () async {
      await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': 100});
      final r = await ask(MessageType.chunkData, {'jobId': 'j1', 'index': 0, 'last': true},
          data: Uint8List(5000));
      expect(r.type, MessageType.error);
    });

    test('a wrong announced hash is rejected at commit and nothing is stored', () async {
      final data = Uint8List.fromList(List.generate(100, (i) => i));
      await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': 100});
      await ask(MessageType.chunkData, {'jobId': 'j1', 'index': 0, 'last': true}, data: data);
      final r = await ask(MessageType.uploadCommit, {'jobId': 'j1', 'ciphertextHash': 'f' * 64});
      expect(r.type, MessageType.error);
      expect(s1.has('abcdef12'), isFalse);
      expect(await s1.files.usedBytes(), 0);
    });

    test('closing the connection releases the reservation', () async {
      await ask(MessageType.storageReserve, {'jobId': 'j1', 'size': 5000});
      expect(await s1.quota.reservedBytes, 5000);
      await inbox.cancel();
      await channel.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await s1.quota.reservedBytes, 0);
    });
  });
}
