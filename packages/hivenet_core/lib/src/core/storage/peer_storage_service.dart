import 'dart:async';
import 'dart:io';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import '../networking/message_protocol.dart';
import '../router_engine/quota_manager.dart';
import '../security/secure_channel.dart';
import 'chunk_manager.dart';
import 'file_store.dart';

/// The storage side of a replica upload (PRD FR-06). Handles one authenticated
/// channel from an uploader:
///
/// ```text
/// STORAGE_RESERVE  -> STORAGE_ACCEPT | STORAGE_REJECT      reserve space
/// UPLOAD_BEGIN     -> TRANSFER_RESUME {nextIndex}          where to continue
/// CHUNK_DATA       -> CHUNK_ACK {index}                    one per chunk
/// UPLOAD_COMMIT    -> REPLICA_COMMITTED {ciphertextHash}   verify + atomic move
/// STORAGE_REJECT   (from the uploader)                     abort: release space
/// ```
///
/// Rules this enforces:
/// - This peer decides whether it has room; the uploader's telemetry is not
///   trusted (PRD FR-02). Space is reserved before any data is accepted.
/// - Data goes to a temporary file. An object becomes a replica only through
///   [FileStore.commit], after its hash matched what the uploader announced.
/// - It stores and serves ciphertext only. It never sees a key.
/// - Everything from the peer is validated: ids, sizes, chunk order.
class PeerStorageService {
  PeerStorageService({
    required this.files,
    required this.chunks,
    required this.quota,
    this.maxObjectBytes = 64 * 1024 * 1024,
    this.chunkSize = 1024 * 1024,
  });

  final FileStore files;
  final ChunkManager chunks;
  final QuotaManager quota;

  /// Largest single object accepted. Images are compressed to a few MB.
  final int maxObjectBytes;

  /// Must equal the chunk size of [chunks] and of the uploader.
  final int chunkSize;

  /// jobId -> what the uploader announced, so commit can check it.
  final Map<String, _Upload> _uploads = {};

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Serves [channel] until it closes. Never throws: a failure ends the
  /// connection, and any space it reserved is released.
  Future<void> serve(SecureChannel channel) async {
    final owned = <String>{};
    try {
      await for (final message in channel.messages) {
        final reply = await _handle(message, channel, owned);
        if (reply != null) await channel.send(reply);
      }
    } catch (_) {
      // A protocol violation or a dropped connection. Fall through to cleanup.
    } finally {
      // Reservations die with the connection; partial data is kept so the
      // uploader can resume within the reservation lifetime.
      for (final job in owned) {
        final key = _key(channel, job);
        if (_uploads.remove(key) != null) await quota.release(key);
      }
      await channel.close();
    }
  }

  Future<MessageEnvelope?> _handle(
    MessageEnvelope m,
    SecureChannel channel,
    Set<String> owned,
  ) async {
    final jobId = m.payload['jobId'];
    if (jobId is! String || !_safeId.hasMatch(jobId)) {
      return _error(m, HiveErrorCode.malformedMessage, 'invalid job id');
    }
    final contentId = m.contentId;
    if (contentId == null || !_safeId.hasMatch(contentId) || contentId.length < 2) {
      return _error(m, HiveErrorCode.malformedMessage, 'invalid content id');
    }
    final key = _key(channel, jobId);

    switch (m.type) {
      case MessageType.storageReserve:
        final size = m.payload['size'];
        if (size is! int || size <= 0 || size > maxObjectBytes) {
          return _reply(m, MessageType.storageReject, {'reason': 'invalid_size'});
        }
        if (await files.exists(contentId)) {
          // Already stored: nothing to reserve, the upload will be a no-op.
          _uploads[key] = _Upload(contentId, size, alreadyStored: true);
          owned.add(jobId);
          return _reply(m, MessageType.storageAccept, {'alreadyStored': true});
        }
        if (!await quota.tryReserve(key, size)) {
          return _reply(m, MessageType.storageReject, {'reason': 'storage_full'});
        }
        _uploads[key] = _Upload(contentId, size);
        owned.add(jobId);
        return _reply(m, MessageType.storageAccept, {});

      case MessageType.uploadBegin:
        final upload = _uploads[key];
        if (upload == null || upload.contentId != contentId) {
          return _error(m, HiveErrorCode.malformedMessage, 'no reservation');
        }
        if (upload.alreadyStored) {
          return _reply(m, MessageType.transferResume, {'nextIndex': _chunkCount(upload.size)});
        }
        return _reply(m, MessageType.transferResume,
            {'nextIndex': await chunks.nextExpectedIndex(_transfer(channel, jobId))});

      case MessageType.chunkData:
        final upload = _uploads[key];
        final data = m.data;
        final index = m.payload['index'];
        if (upload == null || upload.alreadyStored || data == null || index is! int) {
          return _error(m, HiveErrorCode.malformedMessage, 'bad chunk');
        }
        // The chunk must lie inside the size that was reserved.
        if (index < 0 || index * chunkSize + data.length > upload.size) {
          return _error(m, HiveErrorCode.oversizedMessage, 'more data than reserved');
        }
        await chunks.writeChunk(
          _transfer(channel, jobId),
          Chunk(index: index, bytes: data, isLast: m.payload['last'] == true),
        );
        return _reply(m, MessageType.chunkAck, {'index': index});

      case MessageType.uploadCommit:
        final upload = _uploads[key];
        final expected = m.payload['ciphertextHash'];
        if (upload == null || upload.contentId != contentId || expected is! String) {
          return _error(m, HiveErrorCode.malformedMessage, 'nothing to commit');
        }
        if (!upload.alreadyStored) {
          // Recheck capacity right before the atomic move (PRD FR-06).
          if (!await quota.canCommit(key)) {
            return _error(m, HiveErrorCode.storageFull, 'no room left to commit');
          }
          try {
            await files.commit(
              temporaryPath: chunks.pathFor(_transfer(channel, jobId)),
              contentId: contentId,
              expectedCiphertextHash: expected,
            );
          } on HiveError catch (e) {
            await quota.release(key);
            _uploads.remove(key);
            return _error(m, e.code, 'commit failed');
          } on FileSystemException {
            // Nothing was uploaded for this job: answer, don't drop the line.
            return _error(m, HiveErrorCode.malformedMessage, 'no data to commit');
          }
        }
        upload.committed = true;
        await quota.release(key); // now counted as stored, not reserved
        _uploads.remove(key);
        return _reply(m, MessageType.replicaCommitted, {'ciphertextHash': expected});

      case MessageType.storageReject:
        // The uploader is abandoning this job.
        await quota.release(key);
        await chunks.discard(_transfer(channel, jobId));
        _uploads.remove(key);
        return null;

      default:
        return _error(m, HiveErrorCode.malformedMessage, 'unexpected ${m.type.wire}');
    }
  }

  // Reservations and partial files are per (peer, job), so one peer cannot
  // touch another peer's upload by guessing its job id.
  // The node id is derived from the peer's key (letters, digits and a dash),
  // and the job id was validated above, so the result is a safe file name.
  String _key(SecureChannel c, String jobId) => '${c.peerNodeId}_$jobId';
  String _transfer(SecureChannel c, String jobId) => _key(c, jobId);

  int _chunkCount(int size) => (size + chunkSize - 1) ~/ chunkSize;

  MessageEnvelope _reply(MessageEnvelope to, MessageType type, Map<String, Object?> payload) =>
      MessageEnvelope(
        type: type,
        requestId: to.requestId,
        senderNodeId: '',
        contentId: to.contentId,
        payload: payload,
      );

  MessageEnvelope _error(MessageEnvelope to, HiveErrorCode code, String detail) =>
      MessageEnvelope(
        type: MessageType.error,
        requestId: to.requestId,
        senderNodeId: '',
        contentId: to.contentId,
        payload: {'code': code.wire, 'detail': detail},
      );
}

class _Upload {
  _Upload(this.contentId, this.size, {this.alreadyStored = false});
  final String contentId;
  final int size;
  final bool alreadyStored;
  bool committed = false;
}
