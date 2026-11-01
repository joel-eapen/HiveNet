import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import '../metadata/local_manifest_repository.dart';
import '../networking/message_protocol.dart';
import '../router_engine/channel_replica_transport.dart';
import '../security/encryption_service.dart';
import '../security/key_store.dart';
import '../security/secure_channel.dart';
import '../storage/chunk_manager.dart';
import '../storage/integrity_checker.dart';
import '../storage/storage_layout.dart';
import '../upload/upload_service.dart';
import 'image_request_manager.dart';

/// Fetches an image by content ID and returns it only after it is verified
/// (PRD FR-08):
///
/// 1. use the local copy if this device uploaded it, otherwise
/// 2. download the encrypted object chunk by chunk from a replica holder;
///    if a holder fails, continue from the same point on the next one
/// 3. check the ciphertext hash from the manifest
/// 4. decrypt with this device's key for the image
/// 5. check the plaintext hashes to the content ID
///
/// Nothing is shown unless every check passed. A holder that serves corrupt
/// data is dropped and the download restarts from another.
class RetrievalService {
  RetrievalService({
    required this.localNodeId,
    required this.layout,
    required this.dial,
    required this.chunks,
    required this.keys,
    required this.encryption,
    required this.integrity,
    required this.manifests,
    required this.replicaHolders,
    this.replyTimeout = const Duration(seconds: 20),
    this.chunkSize = 1024 * 1024,
  });

  final String localNodeId;
  final StorageLayout layout;
  final DialPeer dial;
  final ChunkManager chunks;
  final KeyStore keys;
  final EncryptionService encryption;
  final IntegrityChecker integrity;
  final LocalManifestRepository manifests;

  /// Devices believed to hold a verified replica, best first.
  final Future<List<String>> Function(String contentId) replicaHolders;
  final Duration replyTimeout;
  final int chunkSize;

  Stream<RetrievalSession> fetch(String contentId) async* {
    final requestId = '$contentId-${DateTime.now().microsecondsSinceEpoch}';
    RetrievalSession at(RetrievalStage s, {double p = 0, String? path, String? host}) =>
        RetrievalSession(
            requestId: requestId,
            contentId: contentId,
            stage: s,
            progress: p,
            localPath: path,
            hostNodeId: host);

    final manifest = await manifests.byId(contentId);
    final expectedHash = manifest?.ciphertextHash;
    if (manifest == null || expectedHash == null) {
      yield at(RetrievalStage.failed);
      return;
    }

    // Without the image key there is nothing to show, however many replicas exist.
    final key = await keys.read(UploadService.keyName(contentId));
    if (key == null) {
      yield at(RetrievalStage.denied);
      return;
    }

    // 1. Our own copy.
    final local = File(layout.outgoingPath(contentId));
    if (await local.exists()) {
      yield at(RetrievalStage.verifying);
      final result = await _open(await local.readAsBytes(), expectedHash, key, contentId);
      if (result != null) {
        yield at(RetrievalStage.ready, p: 1, path: result);
        return;
      }
    }

    // 2. Replicas.
    final holders = await replicaHolders(contentId);
    if (holders.isEmpty) {
      yield at(RetrievalStage.unavailable);
      return;
    }

    final transferId = 'dl-${contentId.substring(0, contentId.length < 32 ? contentId.length : 32)}';
    var denied = false;
    for (final holder in holders) {
      yield at(RetrievalStage.locatingReplica, host: holder);
      SecureChannel? channel;
      StreamIterator<MessageEnvelope>? inbox;
      try {
        channel = await dial(holder);
        inbox = StreamIterator(channel.messages);

        var index = await chunks.nextExpectedIndex(transferId);
        var total = 0;
        var done = false;
        while (!done) {
          await channel.send(MessageEnvelope(
            type: MessageType.getImage,
            requestId: requestId,
            senderNodeId: localNodeId,
            contentId: contentId,
            payload: {'index': index},
          ));
          final has = await inbox.moveNext().timeout(replyTimeout);
          if (!has) throw HiveError(code: HiveErrorCode.peerDisconnected, message: 'disconnected');
          final reply = inbox.current;

          if (reply.type == MessageType.accessDenied) {
            denied = true;
            break;
          }
          if (reply.type != MessageType.chunkData || reply.data == null) {
            throw HiveError(code: HiveErrorCode.peerDisconnected, message: 'holder cannot serve');
          }
          total = reply.payload['size'] as int;
          final isLast = reply.payload['last'] == true;
          await chunks.writeChunk(
              transferId, Chunk(index: index, bytes: reply.data!, isLast: isLast));
          index++;
          done = isLast;
          yield at(RetrievalStage.downloading,
              p: total == 0 ? 0 : (index * chunkSize / total).clamp(0, 1).toDouble(),
              host: holder);
        }
        if (denied) break;

        // 3-5. Verify, decrypt, verify again.
        yield at(RetrievalStage.verifying, p: 1, host: holder);
        final cipher = await File(chunks.pathFor(transferId)).readAsBytes();
        final path = await _open(cipher, expectedHash, key, contentId);
        await chunks.discard(transferId);
        if (path != null) {
          yield at(RetrievalStage.ready, p: 1, path: path, host: holder);
          return;
        }
        // Corrupt copy: forget it and try the next holder from the start.
      } catch (_) {
        // Holder unreachable, slow, or misbehaving. Partial data is kept so the
        // next holder continues from the same point.
      } finally {
        await inbox?.cancel();
        await channel?.close();
      }
    }

    await chunks.discard(transferId);
    yield at(denied ? RetrievalStage.denied : RetrievalStage.unavailable);
  }

  /// Verifies and decrypts [cipher]. Returns the path of the verified image,
  /// or null if anything about it is wrong.
  Future<String?> _open(
    Uint8List cipher,
    String expectedHash,
    Uint8List key,
    String contentId,
  ) async {
    if (await integrity.sha256OfBytes(cipher) != expectedHash.toLowerCase()) return null;
    final Uint8List plain;
    try {
      plain = await encryption.decrypt(ciphertext: cipher, imageKey: key);
    } on HiveError {
      return null;
    }
    if (await integrity.sha256OfBytes(plain) != contentId.toLowerCase()) return null;

    final out = File('${layout.retrievedCacheDir}/$contentId.img');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(plain, flush: true);
    return out.path;
  }
}
