import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../adapters/app_paths.dart';
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

final imageCompressorProvider =
    Provider<ImageCompressor>((ref) => const FlutterImageCompressor());

final peerDiscoveryProvider =
    Provider<PeerDiscovery>((ref) => const BonsoirPeerDiscovery());

// --- Core services (stubs until their milestones) ---

final compressionConfigProvider =
    Provider<CompressionConfig>((ref) => const CompressionConfig());

final networkConfigProvider =
    Provider<NetworkConfig>((ref) => const NetworkConfig());

final storageRouterProvider =
    Provider<StorageRouter>((ref) => const UnimplementedStorageRouter());

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
  @override
  bool build() => true;
  void set(bool value) => state = value;
}

final demoModeProvider =
    NotifierProvider<DemoModeNotifier, bool>(DemoModeNotifier.new);

/// In-memory for now. Persisting it is part of Milestone 1.
class OnboardingCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void complete() => state = true;
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(
        OnboardingCompleteNotifier.new);

class DeviceNameNotifier extends Notifier<String> {
  @override
  String build() => 'This device';
  void set(String name) => state = name;
}

final deviceNameProvider =
    NotifierProvider<DeviceNameNotifier, String>(DeviceNameNotifier.new);

/// Real value comes from discovery in Milestone 2. Defaults to offline rather
/// than pretending to be connected.
class NetworkStateNotifier extends Notifier<NetworkState> {
  @override
  NetworkState build() => NetworkState.offline;
}

final networkStateProvider =
    NotifierProvider<NetworkStateNotifier, NetworkState>(
        NetworkStateNotifier.new);
