/// Exchanges manifest events with a paired peer (PRD FR-07, FR-11). Syncs
/// manifests, not original image bytes. Thumbnails follow the image's view
/// policy.
abstract interface class MetadataSync {
  Future<void> syncWith(String peerNodeId);
}

class UnimplementedMetadataSync implements MetadataSync {
  const UnimplementedMetadataSync();

  @override
  Future<void> syncWith(String peerNodeId) =>
      throw UnimplementedError('MetadataSync: Milestone 5');
}
