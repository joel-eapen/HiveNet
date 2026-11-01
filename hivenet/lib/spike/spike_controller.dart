// THROWAWAY Milestone 0 spike code.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../adapters/secure_key_store.dart';
import 'spike_checks.dart';
import 'spike_discovery.dart';
import 'spike_media.dart';
import 'spike_net.dart';

class SpikeController extends ChangeNotifier with WidgetsBindingObserver {
  final SpikeReport report = SpikeReport();
  final SecureKeyStore _keys = SecureKeyStore();
  final SpikeDiscovery _discovery = SpikeDiscovery();

  late final Directory dir;
  late final SpikeNode node;
  String nodeId = '';
  List<String> localAddresses = [];
  final Map<String, FoundPeer> found = {};
  CompressOutcome? lastCompressed;
  File? lastCompressedFile;
  Uint8List? lastReceivedImage;
  String? lastReceivedInfo;
  bool busy = false;
  Timer? _ticker;

  String get platform => Platform.operatingSystem;
  List<PeerBeat> get heartbeats => node.peers.values.toList();

  static const _identityKey = 'spike.identity';
  static const _createdKey = 'spike.identity.created';

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    dir = Directory('${(await getApplicationSupportDirectory()).path}/spike')
      ..createSync(recursive: true);

    await _checkKeyPersistence();

    node = SpikeNode(
      nodeId: nodeId,
      deviceName: '$platform device',
      dir: dir,
      log: report.log,
    )
      ..onPeersChanged = notifyListeners
      ..onReceived = _handleReceived;
    await node.start();

    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    localAddresses = [
      for (final i in ifaces)
        for (final a in i.addresses) '${i.name} ${a.address}',
    ];

    report.addListener(notifyListeners);
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _watchPeers());
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _discovery.stop();
    node.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    report.log('app lifecycle: ${state.name}');
  }

  // ------------------------------------------------------------- 7: keys

  Future<void> _checkKeyPersistence() async {
    try {
      final existing = await _keys.read(_identityKey);
      if (existing != null) {
        final created = await _keys.read(_createdKey);
        final when = created == null ? 'unknown time' : String.fromCharCodes(created);
        final fp = sha256.convert(existing).toString().substring(0, 12);
        nodeId = 'spike-${fp.substring(0, 8)}';
        report.setCheck('keys', CheckStatus.pass,
            'Key found from an earlier run (fingerprint $fp, created $when). It persisted across restart.');
      } else {
        final key = Uint8List.fromList(
            List.generate(32, (_) => Random.secure().nextInt(256)));
        await _keys.write(_identityKey, key);
        await _keys.write(_createdKey,
            Uint8List.fromList(DateTime.now().toIso8601String().codeUnits));
        final fp = sha256.convert(key).toString().substring(0, 12);
        nodeId = 'spike-${fp.substring(0, 8)}';
        report.setCheck('keys', CheckStatus.partial,
            'New key written (fingerprint $fp). Fully close and reopen the app: the same fingerprint must appear.');
      }
    } catch (e) {
      nodeId = 'spike-nokey';
      report.setCheck('keys', CheckStatus.fail, 'Secure storage failed: $e');
    }
  }

  Future<void> resetKey() async {
    await _keys.delete(_identityKey);
    await _keys.delete(_createdKey);
    report.checks['keys']!
      ..status = CheckStatus.pending
      ..detail = 'Key deleted. Restart the app to create a new one.';
    report.log('identity key deleted');
    notifyListeners();
  }

  // ------------------------------------------------- 1, 2: permission, mDNS

  Future<void> startDiscovery() async {
    if (_discovery.running) return;
    try {
      await _discovery.start(
        nodeId: nodeId,
        deviceName: '$platform device',
        platform: platform,
        port: node.port,
        log: report.log,
        onFound: (peer) {
          found[peer.nodeId] = peer;
          report.setCheck(
              'discovery',
              CheckStatus.pass,
              'Found ${peer.nodeId} (${peer.platform}) at ${peer.host}:${peer.port} via mDNS.');
          notifyListeners();
        },
        onLost: (name) {
          found.removeWhere((_, p) => p.serviceName == name);
          notifyListeners();
        },
      );
      report.setCheck(
          'permission',
          CheckStatus.partial,
          'Discovery started without an error on $platform. On iOS confirm the local-network prompt appeared, then check that denying it is handled.');
    } catch (e) {
      report.setCheck('permission', CheckStatus.fail, 'Discovery failed to start: $e');
    }
    notifyListeners();
  }

  // ----------------------------------------------------- 3, 4: transfer

  Future<File> _testFile(int bytes) async {
    final f = File('${dir.path}/spike_random_${bytes ~/ (1024 * 1024)}MiB.bin');
    if (!f.existsSync() || f.lengthSync() != bytes) {
      final rnd = Random.secure();
      final sink = f.openWrite();
      for (var i = 0; i < bytes ~/ 65536; i++) {
        sink.add(Uint8List.fromList(List.generate(65536, (_) => rnd.nextInt(256))));
      }
      await sink.close();
    }
    return f;
  }

  /// Sends a 5 MiB file, drops the connection after 2 chunks, then resumes.
  Future<void> interruptedTransfer(String host, int port) async {
    await _guard('interrupted transfer', () async {
      final file = await _testFile(5 * 1024 * 1024);
      final first = await node.send(
        host: host,
        port: port,
        file: file,
        name: 'spike_5MiB.bin',
        interruptAfterChunks: 2,
      );
      report.log('first attempt interrupted after ${first.ackedBytes} bytes');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final second = await node.send(
        host: host,
        port: port,
        file: file,
        name: 'spike_5MiB.bin',
      );
      final local = host == '127.0.0.1' || host == 'localhost';
      final resumed = second.resumedFrom == first.ackedBytes && second.resumedFrom > 0;
      report.log('second attempt resumed from ${second.resumedFrom}, hash ok=${second.ok}');
      final scope = local ? 'loopback only' : 'to $host (${second.receiverPlatform})';
      report.setCheck(
        'transfer',
        second.ok ? (local ? CheckStatus.partial : CheckStatus.pass) : CheckStatus.fail,
        '5 MiB in 1 MiB chunks with per-chunk ACKs, SHA-256 ${second.ok ? "verified" : "MISMATCH"} ($scope).',
      );
      report.setCheck(
        'resume',
        (second.ok && resumed)
            ? (local ? CheckStatus.partial : CheckStatus.pass)
            : CheckStatus.fail,
        'Connection dropped at ${first.ackedBytes} bytes, resumed from ${second.resumedFrom} ($scope).',
      );
    });
  }

  // ------------------------------------------------------- 5, 6: images

  Future<void> compressGenerated() async {
    await _guard('compress generated image', () async {
      final png = await generateTestPng(dir);
      await _compress(png.path, 'generated 3000x2000 PNG');
    });
  }

  /// Compresses every file in `<app files>/spike/inbox/`. Lets test images be
  /// pushed with adb instead of driving the system picker.
  Future<void> compressInbox() async {
    await _guard('compress inbox', () async {
      final inbox = Directory('${dir.path}/inbox');
      final files = inbox.existsSync()
          ? (inbox.listSync().whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
          : <File>[];
      if (files.isEmpty) {
        report.log('inbox is empty: ${inbox.path}');
        return;
      }
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        try {
          await _compress(f.path, name);
        } catch (e) {
          report.log('$name: FAILED: $e');
        }
      }
    });
  }

  Future<void> pickAndCompress() async {
    await _guard('pick and compress', () async {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty || picked.first.path == null) {
        report.log('picker cancelled');
        return;
      }
      final f = picked.first;
      await _compress(f.path!, 'picked "${f.name}" (.${f.extension})');
    });
  }

  Future<void> _compress(String path, String label) async {
    try {
      final r = await compressForSpike(path);
      final out = File('${dir.path}/spike_compressed.jpg');
      await out.writeAsBytes(r.bytes);
      lastCompressed = r;
      lastCompressedFile = out;
      final exifNote = r.containsExif
          ? 'EXIF STILL PRESENT (bad)'
          : (r.inputHadExif ? 'EXIF removed' : 'input had no EXIF');
      final line =
          '$label: input ${r.inputFormat} ${r.inputDims} ${r.inputBytes} B -> JPEG '
          '${r.bytes.length} B ${r.width}x${r.height}, $exifNote, '
          'marker ${r.markerCorner}, sha256 ${r.sha256.substring(0, 12)}';
      report.log(line);
      final isHeif = r.inputFormat.startsWith('ISO-BMFF');
      report.setCheck(
        'import',
        r.containsExif ? CheckStatus.fail : CheckStatus.partial,
        '$line${isHeif ? "" : ". Still need an iPhone HEIC sample."}',
      );
      if (isHeif && !r.containsExif) {
        report.setCheck('import', CheckStatus.pass, line);
      }
    } catch (e) {
      report.setCheck('import', CheckStatus.fail, 'Could not import/compress: $e');
      rethrow;
    }
    notifyListeners();
  }

  Future<void> sendCompressed(String host, int port) async {
    final file = lastCompressedFile;
    if (file == null) {
      report.log('compress an image first');
      return;
    }
    await _guard('send compressed image', () async {
      final r = await node.send(
          host: host, port: port, file: file, name: 'compressed.jpg', isImage: true);
      report.log('image sent: hash ok=${r.ok}, receiver=${r.receiverPlatform}, note=${r.receiverNote}');
      final cross = r.receiverPlatform != null && r.receiverPlatform != platform;
      report.setCheck(
        'crossdecode',
        r.ok
            ? (cross ? CheckStatus.pass : CheckStatus.partial)
            : CheckStatus.fail,
        'Sent from $platform, receiver ${r.receiverPlatform} reports: ${r.receiverNote}. '
        '${cross ? "Different platforms." : "Same platform: repeat across Android and iPhone."}',
      );
    });
  }

  Future<String?> _handleReceived(ReceivedFile f) async {
    report.log('received ${f.name} (${f.sizeBytes} B) hash ok=${f.hashOk} from ${f.senderPlatform}');
    if (!f.isImage) return null;
    try {
      final bytes = await File(f.path).readAsBytes();
      final dims = await decodeDimensions(bytes);
      lastReceivedImage = bytes;
      lastReceivedInfo = 'decoded $dims on $platform, sha256 ${f.sha256.substring(0, 12)}';
      final cross = f.senderPlatform != platform;
      report.setCheck(
        'crossdecode',
        cross ? CheckStatus.pass : CheckStatus.partial,
        'Received from ${f.senderPlatform}, hash verified, decoded $dims on $platform.'
        '${cross ? "" : " Same platform: repeat across Android and iPhone."}',
      );
      notifyListeners();
      return 'decoded $dims on $platform';
    } catch (e) {
      report.setCheck('crossdecode', CheckStatus.fail, 'Received but could not decode: $e');
      return 'DECODE FAILED: $e';
    }
  }

  // ------------------------------------------------------- 8: background

  Future<void> link(String host, int port) async {
    await _guard('heartbeat link', () => node.openLink(host, port));
  }

  void _watchPeers() {
    var changed = false;
    for (final p in node.peers.values) {
      if (!p.isOnline && !p.reportedUnavailable) {
        p.reportedUnavailable = true;
        changed = true;
        report.log('peer ${p.nodeId} (${p.platform}) stopped heartbeating: now unavailable');
        report.setCheck(
          'background',
          CheckStatus.pass,
          'Peer ${p.nodeId} (${p.platform}) missed its 15 s lease and was marked unavailable. '
          'Confirm the cause was backgrounding it, not a network drop.',
        );
      }
    }
    if (changed || node.peers.isNotEmpty) notifyListeners();
  }

  // ------------------------------------------------------------- plumbing

  Future<void> _guard(String name, Future<void> Function() body) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      report.log('$name failed: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selfTest() async {
    await interruptedTransfer('127.0.0.1', node.port);
  }
}
