import '../../shared/models/replica_record.dart';

/// Finds believed replica locations for a content ID (PRD FR-08). Results are
/// evidence, not proof: callers must revalidate before retrieving.
abstract interface class ContentLocator {
  Future<List<ReplicaRecord>> locate(String contentId);
}

class UnimplementedContentLocator implements ContentLocator {
  const UnimplementedContentLocator();

  @override
  Future<List<ReplicaRecord>> locate(String contentId) =>
      throw UnimplementedError('ContentLocator: Milestone 5');
}
