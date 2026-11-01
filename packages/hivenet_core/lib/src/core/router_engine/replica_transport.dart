/// The object being replicated. The file at [objectPath] is the encrypted
/// object, identical for every destination (it is never re-encrypted per peer).
class ReplicationSource {
  const ReplicationSource({
    required this.contentId,
    required this.objectPath,
    required this.ciphertextHash,
    required this.sizeBytes,
  });

  final String contentId;
  final String objectPath;
  final String ciphertextHash;
  final int sizeBytes;
}

class ReserveOutcome {
  const ReserveOutcome.accepted()
      : accepted = true,
        reason = null;
  const ReserveOutcome.rejected(this.reason) : accepted = false;

  final bool accepted;
  final String? reason;
}

/// One peer-to-peer conversation per call, mapped onto the PRD FR-06 flow:
/// `STORAGE_RESERVE`, `UPLOAD_BEGIN`/`CHUNK_DATA`, `UPLOAD_COMMIT`.
///
/// Implementations may throw (unreachable peer, timeout, `HiveError`); the
/// replication manager treats any throw as "this peer failed" and carries on
/// with the others.
abstract interface class ReplicaTransport {
  /// Asks the peer to reserve space. The peer re-checks its own capacity.
  Future<ReserveOutcome> reserve({
    required String nodeId,
    required String jobId,
    required String contentId,
    required int sizeBytes,
  });

  /// Streams the object in chunks, resuming if the peer already holds some.
  Future<void> upload({
    required String nodeId,
    required String jobId,
    required ReplicationSource source,
  });

  /// Tells the peer to verify the full object against [ciphertextHash] and move
  /// it into its object store atomically. Returns the hash the peer reports.
  Future<String> commit({
    required String nodeId,
    required String jobId,
    required String contentId,
    required String ciphertextHash,
  });

  /// Best effort: release a reservation and drop partial data.
  Future<void> abort({required String nodeId, required String jobId});
}
