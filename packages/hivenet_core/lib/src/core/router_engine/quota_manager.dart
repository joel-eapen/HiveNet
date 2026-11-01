/// Destination-side capacity control (PRD FR-06). Reservations are atomic so
/// concurrent uploads cannot over-allocate disk, and capacity is re-checked
/// immediately before commit.
abstract interface class QuotaManager {
  /// Returns false when the quota or safety margin would be exceeded.
  Future<bool> tryReserve(String reservationId, int bytes);
  Future<void> release(String reservationId);

  /// Final check before atomically committing a replica.
  Future<bool> canCommit(String reservationId);
  Future<int> get reservedBytes;
}

class UnimplementedQuotaManager implements QuotaManager {
  const UnimplementedQuotaManager();

  @override
  Future<bool> tryReserve(String reservationId, int bytes) =>
      throw UnimplementedError('QuotaManager: Milestone 4');

  @override
  Future<void> release(String reservationId) =>
      throw UnimplementedError('QuotaManager: Milestone 4');

  @override
  Future<bool> canCommit(String reservationId) =>
      throw UnimplementedError('QuotaManager: Milestone 4');

  @override
  Future<int> get reservedBytes =>
      throw UnimplementedError('QuotaManager: Milestone 4');
}
