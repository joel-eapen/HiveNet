import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../shared/models/enums.dart';
import '../../shared/models/image_manifest.dart';
import '../../shared/models/jobs.dart';
import '../../shared/models/peer_telemetry.dart';
import '../metadata/local_manifest_repository.dart';
import '../router_engine/replica_transport.dart';
import '../router_engine/replication_manager.dart';
import '../router_engine/replication_store.dart';
import '../router_engine/storage_router.dart';
import '../security/encryption_service.dart';
import '../security/key_store.dart';
import '../storage/integrity_checker.dart';
import '../storage/storage_layout.dart';

/// Which step an upload is on, for the progress UI.
enum UploadStage { hashing, encrypting, planning, replicating, finished }

class UploadRequest {
  const UploadRequest({
    required this.compressedPath,
    required this.fileName,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.importance,
    required this.visibility,
  });

  /// The already-compressed image. Original bytes never get this far (PRD FR-03).
  final String compressedPath;
  final String fileName;
  final String mimeType;
  final int width;
  final int height;
  final Importance importance;
  final ImageVisibility visibility;
}

class UploadUpdate {
  const UploadUpdate(this.stage, {this.contentId, this.job, this.message, this.plan});

  final UploadStage stage;
  final String? contentId;

  /// Present from the planning stage on; its status is the truthful outcome.
  final UploadJob? job;
  final String? message;

  /// Which devices were chosen and why. Set once, on the update that follows
  /// planning.
  final PlacementPlan? plan;
}

/// Runs one image from "compressed file" to "stored on other devices":
///
/// 1. content ID = SHA-256 of the compressed bytes
/// 2. encrypt with a fresh per-image key; keep the key on this device only
/// 3. record the gallery entry as pending
/// 4. choose storage peers, then replicate (see `DefaultReplicationManager`)
/// 5. set the entry's availability from the real outcome
///
/// The entry only becomes `available` when the replication manager reports
/// `COMPLETED`, i.e. every required replica is verified.
class UploadService {
  UploadService({
    required this.localNodeId,
    required this.layout,
    required this.encryption,
    required this.integrity,
    required this.keys,
    required this.manifests,
    required this.router,
    required this.replication,
    required this.store,
    required this.peerTelemetry,
    DateTime Function()? clock,
    String Function()? newJobId,
  })  : _clock = clock ?? DateTime.now,
        _newJobId = newJobId ?? (() => const Uuid().v4());

  final String localNodeId;
  final StorageLayout layout;
  final EncryptionService encryption;
  final IntegrityChecker integrity;
  final KeyStore keys;
  final LocalManifestRepository manifests;
  final StorageRouter router;
  final ReplicationManager replication;
  final ReplicationStore store;

  /// Current view of nearby peers (from discovery and heartbeats).
  final Future<List<PeerTelemetry>> Function() peerTelemetry;
  final DateTime Function() _clock;
  final String Function() _newJobId;

  /// Where this device keeps the key for an image it uploaded.
  static String keyName(String contentId) => 'imagekey.$contentId';

  Stream<UploadUpdate> upload(UploadRequest request) async* {
    yield const UploadUpdate(UploadStage.hashing);
    final Uint8List plain;
    try {
      plain = await File(request.compressedPath).readAsBytes();
    } on FileSystemException {
      throw StateError('The compressed image could not be read.');
    }
    final contentId = await integrity.sha256OfBytes(plain);

    yield UploadUpdate(UploadStage.encrypting, contentId: contentId);
    final encrypted = await encryption.encrypt(plain);

    // The key is saved before any copy leaves this device. If it were lost
    // after replicas existed, the image would be unreadable forever.
    await keys.write(keyName(contentId), encrypted.imageKey);

    final objectPath = layout.outgoingPath(contentId);
    await File(objectPath).parent.create(recursive: true);
    await File(objectPath).writeAsBytes(encrypted.ciphertext, flush: true);

    final existing = await manifests.byId(contentId);
    await manifests.save(ImageManifest(
      contentId: contentId,
      ownerNodeId: localNodeId,
      fileName: request.fileName,
      mimeType: request.mimeType,
      fileSizeBytes: plain.length,
      width: request.width,
      height: request.height,
      importance: request.importance,
      visibility: request.visibility,
      desiredReplicationFactor: request.importance.desiredReplicationFactor,
      createdAt: existing?.createdAt ?? _clock().toUtc(),
      manifestVersion: (existing?.manifestVersion ?? 0) + 1,
      availabilityStatus: AvailabilityStatus.pending,
      ciphertextHash: encrypted.ciphertextHash,
      encryptionMetadata: const {'cipher': 'AES-256-GCM', 'format': 1},
    ));

    yield UploadUpdate(UploadStage.planning, contentId: contentId);
    final plan = await router.plan(
      PlacementRequest(
        sizeBytes: encrypted.ciphertext.length,
        importance: request.importance,
        excludeNodeIds: {localNodeId},
      ),
      await peerTelemetry(),
    );

    yield UploadUpdate(UploadStage.replicating, contentId: contentId, plan: plan);

    final job = UploadJob(
      jobId: _newJobId(),
      contentId: contentId,
      status: UploadState.created,
      requestedReplicationFactor: request.importance.desiredReplicationFactor,
      createdAt: _clock().toUtc(),
    );
    await store.saveJob(job);

    final source = ReplicationSource(
      contentId: contentId,
      objectPath: objectPath,
      ciphertextHash: encrypted.ciphertextHash,
      sizeBytes: encrypted.ciphertext.length,
    );

    UploadJob last = job;
    await for (final state in replication.replicate(job, plan, source)) {
      last = state;
      yield UploadUpdate(UploadStage.replicating, contentId: contentId, job: state);
    }

    await manifests.setAvailability(contentId, availabilityFor(last.status));
    yield UploadUpdate(UploadStage.finished,
        contentId: contentId, job: last, message: last.failureReason);
  }

  /// The gallery state that honestly describes a job's final status.
  static AvailabilityStatus availabilityFor(UploadState state) => switch (state) {
        UploadState.completed => AvailabilityStatus.available,
        UploadState.underReplicated => AvailabilityStatus.underReplicated,
        _ => AvailabilityStatus.pending,
      };
}
