import '../../shared/models/image_manifest.dart';
import '../../shared/models/manifest_event.dart';

/// Local view of owner-authoritative manifests (PRD FR-07). One device's
/// SQLite is never the network-wide source of truth; state is rebuilt from
/// signed, monotonically versioned events and tombstones.
abstract interface class ManifestStore {
  /// Verifies the owner signature and version, then appends. Returns false for
  /// stale or duplicate events.
  Future<bool> apply(ManifestEvent event);

  Future<ImageManifest?> current(String contentId);
  Stream<List<ImageManifest>> watchAll();

  /// Events from [originNodeId] with version greater than [afterVersion].
  Future<List<ManifestEvent>> eventsSince(String originNodeId, int afterVersion);
}

class UnimplementedManifestStore implements ManifestStore {
  const UnimplementedManifestStore();

  @override
  Future<bool> apply(ManifestEvent event) =>
      throw UnimplementedError('ManifestStore: Milestone 5');

  @override
  Future<ImageManifest?> current(String contentId) =>
      throw UnimplementedError('ManifestStore: Milestone 5');

  @override
  Stream<List<ImageManifest>> watchAll() => const Stream.empty();

  @override
  Future<List<ManifestEvent>> eventsSince(
          String originNodeId, int afterVersion) =>
      throw UnimplementedError('ManifestStore: Milestone 5');
}
