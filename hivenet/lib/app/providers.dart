import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../adapters/app_paths.dart';
import '../adapters/app_settings.dart';
import '../demo/demo_data.dart';
import 'runtime/hivenet_runtime.dart';
import '../adapters/bonsoir_peer_discovery.dart';
import '../adapters/flutter_image_compressor.dart';
import '../adapters/secure_key_store.dart';
import 'network_state.dart';

/// Overridden in `main()` after the filesystem layout is created.
final appPathsProvider = Provider<AppPaths>(
  (ref) => throw UnimplementedError('appPathsProvider must be overridden'),
);

/// Overridden in `main()` with the file-backed database; tests override it
/// with an in-memory one.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

// --- Adapters (Flutter-dependent implementations of core interfaces) ---

final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

/// This installation's identity. The private seed lives in the platform
/// secure store; `loadOrCreate` must be called once at startup before signing.
final deviceIdentityServiceProvider = Provider<DeviceIdentityService>(
  (ref) => Ed25519DeviceIdentityService(
    keyStore: ref.watch(keyStoreProvider),
    platform: Platform.isIOS ? DevicePlatform.ios : DevicePlatform.android,
  ),
);

final imageCompressorProvider =
    Provider<ImageCompressor>((ref) => const FlutterImageCompressor());

final peerDiscoveryProvider =
    Provider<PeerDiscovery>((ref) => BonsoirPeerDiscovery());

// --- Core services (stubs until their milestones) ---

final compressionConfigProvider =
    Provider<CompressionConfig>((ref) => const CompressionConfig());

final networkConfigProvider =
    Provider<NetworkConfig>((ref) => const NetworkConfig());

final nodeScorerProvider =
    Provider<NodeScorer>((ref) => const DeterministicNodeScorer());

/// Peers that are paired and not revoked. Read on every placement, so a
/// revocation takes effect on the next upload.
Future<Set<String>> _pairedNodeIds(AppDatabase db) async {
  final rows = await db.trustedDevicesDao.getAll();
  return {
    for (final r in rows)
      if (r.trustStatus == TrustStatus.paired.wire && r.revokedAt == null)
        r.nodeId,
  };
}

final storageRouterProvider = Provider<StorageRouter>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DeterministicStorageRouter(
    trustedNodeIds: () => _pairedNodeIds(db),
    scorer: ref.watch(nodeScorerProvider),
    // The AI ranker is optional and off until it is evaluated (PRD FR-05).
    decisionModel: ref.watch(decisionModelProvider),
    policy: EligibilityPolicy.fromNetwork(ref.watch(networkConfigProvider)),
  );
});

final replicationStoreProvider = Provider<ReplicationStore>(
    (ref) => DriftReplicationStore(ref.watch(appDatabaseProvider)));

/// Placeholder contribution limit until the Storage settings screen lets the
/// user choose one (PRD FR-12).
const int kPlaceholderContributionBytes = 1024 * 1024 * 1024;

final quotaManagerProvider = Provider<QuotaManager>((ref) {
  final files = ref.watch(fileStoreProvider);
  return LocalQuotaManager(
    quotaBytes: kPlaceholderContributionBytes,
    storedBytes: files.usedBytes,
  );
});

/// AI ranking is optional and cannot block uploads (PRD FR-05).
final decisionModelProvider =
    Provider<DecisionModelAdapter>((ref) => const NoopDecisionModel());

/// Denies everything until real authorization exists (PRD FR-09A).
final accessControlProvider =
    Provider<AccessControl>((ref) => const DenyAllAccessControl());

final encryptionServiceProvider =
    Provider<EncryptionService>((ref) => AesGcmEncryptionService());

final integrityCheckerProvider =
    Provider<IntegrityChecker>((ref) => const Sha256IntegrityChecker());

final messageFramingProvider = Provider<MessageFraming>(
  (ref) => LengthPrefixedFraming(
    maxFrameBytes: ref.watch(networkConfigProvider).maxFrameBytes,
  ),
);

final chunkManagerProvider = Provider<ChunkManager>(
  (ref) => FileChunkManager(
    ref.watch(appPathsProvider).layout,
    chunkSize: ref.watch(networkConfigProvider).chunkSizeBytes,
  ),
);

final fileStoreProvider = Provider<FileStore>(
  (ref) => LocalFileStore(
    ref.watch(appPathsProvider).layout,
    ref.watch(integrityCheckerProvider),
  ),
);

final pairingServiceProvider =
    Provider<PairingService>((ref) => const UnimplementedPairingService());

final replicationManagerProvider = Provider<ReplicationManager>(
    (ref) => const UnimplementedReplicationManager());

final imageRequestManagerProvider = Provider<ImageRequestManager>(
    (ref) => const UnimplementedImageRequestManager());

// --- UI state ---

/// Demo fixtures are shown only while this is true, always with a banner.
/// Defaults to on for the skeleton; production repositories never read demo
/// data.
class DemoModeNotifier extends Notifier<bool> {
  /// Live data when the runtime exists. Fixtures only when there is none.
  @override
  bool build() => ref.read(runtimeProvider) == null;
  void set(bool value) => state = value;
}

final demoModeProvider =
    NotifierProvider<DemoModeNotifier, bool>(DemoModeNotifier.new);

/// In-memory for now. Persisting it is part of Milestone 1.
class OnboardingCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(appSettingsProvider)?.onboardingComplete ?? false;
  void complete() {
    state = true;
    final settings = ref.read(appSettingsProvider);
    if (settings != null) {
      settings.onboardingComplete = true;
      settings.save();
    }
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(
        OnboardingCompleteNotifier.new);

class DeviceNameNotifier extends Notifier<String> {
  @override
  String build() => ref.read(appSettingsProvider)?.deviceName ?? 'This device';
  void set(String name) {
    state = name;
    final settings = ref.read(appSettingsProvider);
    if (settings != null) {
      settings.deviceName = name;
      settings.save();
    }
    ref.read(runtimeProvider)?.deviceName = name;
  }
}

final deviceNameProvider =
    NotifierProvider<DeviceNameNotifier, String>(DeviceNameNotifier.new);

/// Derived from real peers: connected if any paired device answered recently,
/// degraded if devices are paired but none answers, offline otherwise.
final networkStateProvider = Provider<NetworkState>((ref) {
  final peers = ref.watch(peersProvider).asData?.value ?? const <PeerView>[];
  final paired = peers.where((p) => p.paired).toList();
  if (ref.watch(runtimeProvider) == null) return NetworkState.offline;
  if (paired.isEmpty) return NetworkState.discovering;
  return paired.any((p) => p.status == PeerStatus.online)
      ? NetworkState.connected
      : NetworkState.degraded;
});

// --- Runtime and live data ---

/// The running HiveNet node. Null only in tests and previews.
final runtimeProvider = Provider<HiveNetRuntime?>((ref) => null);

final appSettingsProvider = Provider<AppSettings?>((ref) => null);

/// Paired and nearby devices. Falls back to demo fixtures only without a runtime.
final peersProvider = StreamProvider<List<PeerView>>((ref) {
  final rt = ref.watch(runtimeProvider);
  if (rt != null) return rt.watchPeers();
  if (!ref.watch(demoModeProvider)) return Stream.value(const []);
  return Stream.value([
    for (final t in DemoData.peers)
      PeerView(
        nodeId: t.nodeId,
        name: t.deviceName,
        status: t.status,
        paired: true,
        host: t.ipAddresses.first,
        port: t.port,
        telemetry: t,
        lastSeen: t.lastSeen,
      ),
  ]);
});

final galleryProvider = StreamProvider<List<ImageManifest>>((ref) {
  final rt = ref.watch(runtimeProvider);
  if (rt != null) return rt.watchGallery();
  return Stream.value(ref.watch(demoModeProvider) ? DemoData.images : const []);
});

/// Upload jobs, newest first.
final jobsProvider = StreamProvider<List<UploadJob>>((ref) {
  final rt = ref.watch(runtimeProvider);
  if (rt != null) {
    return rt.db.uploadJobsDao.watchAll().map((rows) => [
          for (final r in rows)
            UploadJob(
              jobId: r.jobId,
              contentId: r.contentId,
              status: enumFromWire(UploadState.values, r.status),
              requestedReplicationFactor: r.requestedReplicationFactor,
              createdAt: r.createdAt.toUtc(),
              completedAt: r.completedAt?.toUtc(),
              failureReason: r.failureReason,
            ),
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }
  if (!ref.watch(demoModeProvider)) return Stream.value(const []);
  return Stream.value([
    UploadJob(
      jobId: 'demo-transfer-1',
      contentId: DemoData.images.first.contentId,
      status: UploadState.transferring,
      requestedReplicationFactor: 2,
      createdAt: DateTime.utc(2026, 11, 1, 10),
    ),
  ]);
});


/// Disk use. Refreshed on demand and when the gallery changes.
final storageStatsProvider = FutureProvider.autoDispose<StorageStats?>((ref) async {
  final rt = ref.watch(runtimeProvider);
  if (rt == null) return null; // nothing to measure: answer at once, don't spin
  ref.watch(galleryProvider);
  return rt.storageStats();
});
