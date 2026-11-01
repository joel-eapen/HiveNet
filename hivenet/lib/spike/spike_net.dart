// THROWAWAY Milestone 0 spike code.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'spike_wire.dart';

const int spikeChunkBytes = 1024 * 1024;

/// A peer seen through hello/heartbeat frames.
class PeerBeat {
  PeerBeat(this.nodeId, this.name, this.platform) : lastBeat = DateTime.now();

  final String nodeId;
  final String name;
  final String platform;
  DateTime lastBeat;

  /// Set once the peer has been seen stale, so the check fires only once.
  bool reportedUnavailable = false;

  Duration get age => DateTime.now().difference(lastBeat);

  /// Mirrors the PRD lease: three missed 5 s heartbeats.
  bool get isOnline => age < const Duration(seconds: 15);
}

class IncomingTransfer {
  IncomingTransfer({
    required this.id,
    required this.total,
    required this.sha256,
    required this.name,
    required this.isImage,
    required this.partPath,
    required this.senderPlatform,
  });

  final String id;
  final int total;
  final String sha256;
  final String name;
  final bool isImage;
  final String partPath;
  final String senderPlatform;
  int received = 0;
  RandomAccessFile? raf;
}

class ReceivedFile {
  ReceivedFile({
    required this.path,
    required this.name,
    required this.sha256,
    required this.hashOk,
    required this.isImage,
    required this.senderPlatform,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final String sha256;
  final bool hashOk;
  final bool isImage;
  final String senderPlatform;
  final int sizeBytes;
}

class SendResult {
  SendResult({
    required this.ok,
    required this.interrupted,
    required this.ackedBytes,
    required this.resumedFrom,
    required this.totalBytes,
    this.receiverPlatform,
    this.receiverNote,
  });

  final bool ok;
  final bool interrupted;
  final int ackedBytes;
  final int resumedFrom;
  final int totalBytes;
  final String? receiverPlatform;
  final String? receiverNote;
}

typedef ReceiveHook = Future<String?> Function(ReceivedFile file);

/// Listens for peers, receives chunked files and tracks heartbeats.
class SpikeNode {
  SpikeNode({
    required this.nodeId,
    required this.deviceName,
    required this.dir,
    required this.log,
  });

  final String nodeId;
  final String deviceName;
  final Directory dir;
  final void Function(String) log;

  ServerSocket? _server;
  final Map<String, IncomingTransfer> incoming = {};
  final Map<String, PeerBeat> peers = {};
  final List<_Link> _links = [];

  /// Called after a file is fully received. The returned text (for example
  /// decoded image dimensions) is sent back to the sender.
  ReceiveHook? onReceived;
  void Function()? onPeersChanged;

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_serve, onError: (Object e) => log('server error: $e'));
    log('TCP server listening on port $port');
  }

  Future<void> stop() async {
    for (final link in List.of(_links)) {
      link.close();
    }
    await _server?.close();
    _server = null;
  }

  // ---------------------------------------------------------------- server

  Future<void> _serve(Socket socket) async {
    final channel = FrameChannel(socket);
    IncomingTransfer? current;
    String? remoteId;
    var remotePlatform = 'unknown';
    try {
      while (true) {
        final frame = await channel.next(timeout: const Duration(seconds: 30));
        switch (frame.type) {
          case SpikeMsg.hello:
            final j = frame.json;
            final helloId = j['nodeId'] as String;
            remotePlatform = j['platform'] as String? ?? 'unknown';
            // Only dedicated heartbeat links count as peers. Short-lived
            // transfer connections must not later look "unavailable", and a
            // node must never list itself (loopback self-test).
            if (j['role'] == 'link' && helloId != nodeId) {
              remoteId = helloId;
              peers[helloId] = PeerBeat(
                  helloId, j['name'] as String? ?? helloId, remotePlatform);
              onPeersChanged?.call();
            }
          case SpikeMsg.heartbeat:
            final id = remoteId;
            if (id != null) {
              peers[id]?.lastBeat = DateTime.now();
              peers[id]?.reportedUnavailable = false;
              onPeersChanged?.call();
            }
          case SpikeMsg.begin:
            current = await _onBegin(channel, frame, remotePlatform);
          case SpikeMsg.chunk:
            final t = current;
            if (t == null) throw StateError('chunk before begin');
            if (t.received + frame.payload.length > t.total) {
              throw StateError('more bytes than announced');
            }
            await t.raf!.writeFrom(frame.payload);
            t.received += frame.payload.length;
            channel.send(SpikeMsg.ack, jsonPayload({'received': t.received}));
            if (t.received == t.total) await _finish(t, channel);
          case SpikeMsg.resumeAt:
          case SpikeMsg.ack:
          case SpikeMsg.done:
            throw StateError('unexpected ${frame.type.name} on server side');
        }
      }
    } on ChannelClosed {
      // Normal end of connection, or a dropped link mid-transfer.
      if (current != null && current.received < current.total) {
        log('connection dropped at ${current.received}/${current.total} bytes '
            'of ${current.name}; partial data kept for resume');
      }
    } catch (e) {
      log('server connection error: $e');
    } finally {
      await current?.raf?.close();
      current?.raf = null;
      socket.destroy();
    }
  }

  Future<IncomingTransfer> _onBegin(
      FrameChannel channel, Frame frame, String senderPlatform) async {
    final j = frame.json;
    final id = j['transferId'] as String;
    final t = incoming.putIfAbsent(
      id,
      () => IncomingTransfer(
        id: id,
        total: j['total'] as int,
        sha256: j['sha256'] as String,
        name: j['name'] as String,
        isImage: j['isImage'] as bool? ?? false,
        partPath: '${dir.path}/$id.part',
        senderPlatform: senderPlatform,
      ),
    );
    await t.raf?.close();
    final file = File(t.partPath);
    // The bytes on disk are the truth about progress after any interruption.
    t.received = await file.exists() ? await file.length() : 0;
    t.raf = await file.open(mode: FileMode.append);
    channel.send(SpikeMsg.resumeAt, jsonPayload({'offset': t.received}));
    if (t.received == t.total) await _finish(t, channel);
    return t;
  }

  Future<void> _finish(IncomingTransfer t, FrameChannel channel) async {
    await t.raf?.close();
    t.raf = null;
    final actual = (await sha256.bind(File(t.partPath).openRead()).first).toString();
    final ok = actual == t.sha256;
    var finalPath = t.partPath;
    String? note;
    if (ok) {
      finalPath = '${dir.path}/recv_${t.name}';
      await File(t.partPath).rename(finalPath);
      final hook = onReceived;
      if (hook != null) {
        note = await hook(ReceivedFile(
          path: finalPath,
          name: t.name,
          sha256: actual,
          hashOk: true,
          isImage: t.isImage,
          senderPlatform: t.senderPlatform,
          sizeBytes: t.total,
        ));
      }
    } else {
      // Never keep corrupt data around for a resume.
      await File(t.partPath).delete();
    }
    incoming.remove(t.id);
    channel.send(
      SpikeMsg.done,
      jsonPayload({
        'ok': ok,
        'sha256': actual,
        'platform': Platform.operatingSystem,
        'note': note,
      }),
    );
  }

  // ---------------------------------------------------------------- client

  /// Sends [file] in 1 MiB chunks with a per-chunk ACK. If [interruptAfterChunks]
  /// is set the socket is destroyed after that many chunks, to test resume.
  Future<SendResult> send({
    required String host,
    required int port,
    required File file,
    required String name,
    bool isImage = false,
    int? interruptAfterChunks,
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final transferId = '$nodeId-${hash.substring(0, 16)}';

    final socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    final channel = FrameChannel(socket);
    try {
      _hello(channel, role: 'transfer');
      channel.send(
        SpikeMsg.begin,
        jsonPayload({
          'transferId': transferId,
          'total': total,
          'sha256': hash,
          'name': name,
          'isImage': isImage,
        }),
      );
      final resume = await channel.next();
      if (resume.type != SpikeMsg.resumeAt) {
        throw StateError('expected resumeAt, got ${resume.type.name}');
      }
      final offset = resume.json['offset'] as int;

      final raf = await file.open();
      try {
        await raf.setPosition(offset);
        var position = offset;
        var chunks = 0;
        while (position < total) {
          final data = await raf.read(min(spikeChunkBytes, total - position));
          channel.send(SpikeMsg.chunk, data);
          final ack = await channel.next();
          if (ack.type != SpikeMsg.ack) {
            throw StateError('expected ack, got ${ack.type.name}');
          }
          position += data.length;
          if (ack.json['received'] != position) {
            throw StateError('ack mismatch: ${ack.json['received']} != $position');
          }
          chunks++;
          onProgress?.call(position, total);
          if (interruptAfterChunks != null &&
              chunks >= interruptAfterChunks &&
              position < total) {
            socket.destroy();
            return SendResult(
              ok: false,
              interrupted: true,
              ackedBytes: position,
              resumedFrom: offset,
              totalBytes: total,
            );
          }
        }
      } finally {
        await raf.close();
      }

      final done = await channel.next();
      if (done.type != SpikeMsg.done) {
        throw StateError('expected done, got ${done.type.name}');
      }
      final j = done.json;
      return SendResult(
        ok: j['ok'] == true,
        interrupted: false,
        ackedBytes: total,
        resumedFrom: offset,
        totalBytes: total,
        receiverPlatform: j['platform'] as String?,
        receiverNote: j['note'] as String?,
      );
    } finally {
      socket.destroy();
    }
  }

  void _hello(FrameChannel channel, {required String role}) => channel.send(
        SpikeMsg.hello,
        jsonPayload({
          'nodeId': nodeId,
          'name': deviceName,
          'platform': Platform.operatingSystem,
          'role': role,
        }),
      );

  // ------------------------------------------------------------- heartbeat

  /// Opens a long-lived connection and sends a heartbeat every 5 seconds.
  /// Deliberately keeps running when the app is backgrounded: the check is
  /// about what the OS actually does to it.
  Future<void> openLink(String host, int port) async {
    final socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    final channel = FrameChannel(socket);
    _hello(channel, role: 'link');
    final link = _Link(channel);
    _links.add(link);
    link.timer = Timer.periodic(const Duration(seconds: 5), (_) {
      try {
        channel.send(SpikeMsg.heartbeat);
      } catch (_) {
        link.close();
      }
    });
    unawaited(channel.closed.then((_) {
      link.close();
      _links.remove(link);
      log('heartbeat link to $host:$port closed');
    }));
    log('heartbeat link opened to $host:$port');
  }
}

class _Link {
  _Link(this.channel);
  final FrameChannel channel;
  Timer? timer;

  void close() {
    timer?.cancel();
    channel.close();
  }
}
