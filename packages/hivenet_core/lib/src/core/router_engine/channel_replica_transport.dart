import 'dart:async';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import '../networking/message_protocol.dart';
import '../security/secure_channel.dart';
import '../storage/chunk_manager.dart';
import 'replica_transport.dart';

/// Opens an authenticated channel to a peer, or throws. Supplied by the app
/// (address book lookup + `SecureChannel.connect`).
typedef DialPeer = Future<SecureChannel> Function(String nodeId);

/// [ReplicaTransport] over [SecureChannel]s. One channel per (peer, job) stays
/// open from reserve until commit or abort.
///
/// Wire flow per peer (see `PeerStorageService`):
/// reserve -> begin (learn the resume point) -> chunks with per-chunk ACKs ->
/// commit -> the peer's verified hash.
class ChannelReplicaTransport implements ReplicaTransport {
  ChannelReplicaTransport({
    required this.dial,
    required this.chunks,
    required this.localNodeId,
    this.replyTimeout = const Duration(seconds: 30),
  });

  final DialPeer dial;

  /// Used only for [ChunkManager.readChunks]; its chunk size must match the
  /// peers'.
  final ChunkManager chunks;
  final String localNodeId;
  final Duration replyTimeout;

  final Map<String, _Session> _sessions = {};

  String _key(String nodeId, String jobId) => '$nodeId|$jobId';

  @override
  Future<ReserveOutcome> reserve({
    required String nodeId,
    required String jobId,
    required String contentId,
    required int sizeBytes,
  }) async {
    final session = await _open(nodeId, jobId);
    try {
      final reply = await session.call(
        _msg(MessageType.storageReserve, jobId, contentId, {'size': sizeBytes}),
        replyTimeout,
      );
      if (reply.type == MessageType.storageAccept) return const ReserveOutcome.accepted();
      if (reply.type == MessageType.storageReject) {
        await _close(nodeId, jobId);
        return ReserveOutcome.rejected('${reply.payload['reason'] ?? 'rejected'}');
      }
      throw _failure(reply);
    } catch (_) {
      await _close(nodeId, jobId);
      rethrow;
    }
  }

  @override
  Future<void> upload({
    required String nodeId,
    required String jobId,
    required ReplicationSource source,
  }) async {
    final session = _sessions[_key(nodeId, jobId)];
    if (session == null) throw StateError('upload without a reservation');

    final begin = await session.call(
      _msg(MessageType.uploadBegin, jobId, source.contentId, {'size': source.sizeBytes}),
      replyTimeout,
    );
    if (begin.type != MessageType.transferResume) throw _failure(begin);
    final nextIndex = begin.payload['nextIndex'];
    if (nextIndex is! int || nextIndex < 0) {
      throw _protocol('peer sent an invalid resume point');
    }

    // Start where the peer says it already has data; this is how an
    // interrupted upload resumes.
    await for (final chunk in chunks.readChunks(source.objectPath, startIndex: nextIndex)) {
      final ack = await session.call(
        MessageEnvelope(
          type: MessageType.chunkData,
          requestId: jobId,
          senderNodeId: localNodeId,
          contentId: source.contentId,
          payload: {'jobId': jobId, 'index': chunk.index, 'last': chunk.isLast},
          data: chunk.bytes,
        ),
        replyTimeout,
      );
      if (ack.type != MessageType.chunkAck || ack.payload['index'] != chunk.index) {
        throw _failure(ack);
      }
    }
  }

  @override
  Future<String> commit({
    required String nodeId,
    required String jobId,
    required String contentId,
    required String ciphertextHash,
  }) async {
    final session = _sessions[_key(nodeId, jobId)];
    if (session == null) throw StateError('commit without a session');
    try {
      final reply = await session.call(
        _msg(MessageType.uploadCommit, jobId, contentId, {'ciphertextHash': ciphertextHash}),
        replyTimeout,
      );
      if (reply.type != MessageType.replicaCommitted) throw _failure(reply);
      final hash = reply.payload['ciphertextHash'];
      if (hash is! String) throw _protocol('peer did not report a hash');
      return hash;
    } finally {
      await _close(nodeId, jobId);
    }
  }

  /// Tells the peer to drop this job, then closes. Never throws.
  @override
  Future<void> abort({required String nodeId, required String jobId}) async {
    final session = _sessions[_key(nodeId, jobId)];
    if (session == null) return;
    try {
      await session.channel.send(_msg(MessageType.storageReject, jobId, session.contentId, {}));
    } catch (_) {}
    await _close(nodeId, jobId);
  }

  // ---------------------------------------------------------------- helpers

  Future<_Session> _open(String nodeId, String jobId) async {
    final key = _key(nodeId, jobId);
    final existing = _sessions[key];
    if (existing != null) return existing;
    final channel = await dial(nodeId);
    if (channel.peerNodeId != nodeId) {
      // We dialled one device and a different one answered.
      await channel.close();
      throw _protocol('connected to a different device than expected');
    }
    return _sessions[key] = _Session(channel);
  }

  Future<void> _close(String nodeId, String jobId) async {
    final session = _sessions.remove(_key(nodeId, jobId));
    await session?.dispose();
  }

  MessageEnvelope _msg(
    MessageType type,
    String jobId,
    String contentId,
    Map<String, Object?> payload,
  ) =>
      MessageEnvelope(
        type: type,
        requestId: jobId,
        senderNodeId: localNodeId,
        contentId: contentId,
        payload: {'jobId': jobId, ...payload},
      );

  HiveError _failure(MessageEnvelope reply) {
    if (reply.type == MessageType.error) {
      final code = reply.payload['code'];
      return HiveError(
        code: HiveErrorCode.values.firstWhere(
          (c) => c.wire == code,
          orElse: () => HiveErrorCode.peerDisconnected,
        ),
        message: 'The storage device refused the request.',
        technicalDetails: '${reply.payload['detail']}',
      );
    }
    return _protocol('unexpected ${reply.type.wire}');
  }

  HiveError _protocol(String detail) => HiveError(
        code: HiveErrorCode.malformedMessage,
        message: 'A storage device sent an unexpected reply.',
        technicalDetails: detail,
      );
}

/// One channel with a request/response helper.
class _Session {
  _Session(this.channel) : _inbox = StreamIterator(channel.messages);

  final SecureChannel channel;
  final StreamIterator<MessageEnvelope> _inbox;
  String contentId = 'xx';

  Future<MessageEnvelope> call(MessageEnvelope request, Duration timeout) async {
    contentId = request.contentId ?? contentId;
    await channel.send(request);
    final has = await _inbox.moveNext().timeout(timeout, onTimeout: () {
      throw TimeoutException('no reply within $timeout');
    });
    if (!has) {
      throw HiveError(
        code: HiveErrorCode.peerDisconnected,
        message: 'The storage device disconnected.',
      );
    }
    return _inbox.current;
  }

  Future<void> dispose() async {
    await _inbox.cancel();
    await channel.close();
  }
}
