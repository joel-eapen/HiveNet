import 'dart:async';

import 'quota_manager.dart';

/// Destination-side capacity control (PRD FR-06).
///
/// Space available for a new reservation is:
///
/// ```text
/// quota - bytesAlreadyStored - bytesCurrentlyReserved
/// ```
///
/// and, when the platform can report real free disk space, the disk must also
/// keep [safetyMarginBytes] free after all reservations.
///
/// Reservations are checked and recorded inside one critical section, so
/// concurrent uploads cannot both claim the last free bytes even though the
/// stored-bytes lookup is asynchronous. Reservations expire, so an uploader
/// that vanishes cannot hold space forever.
///
/// After a successful commit the caller calls [release]: the bytes are then
/// counted as stored instead of reserved.
class LocalQuotaManager implements QuotaManager {
  LocalQuotaManager({
    required this.quotaBytes,
    required this.storedBytes,
    this.freeDiskBytes,
    this.safetyMarginBytes = 256 * 1024 * 1024,
    this.reservationTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now {
    if (quotaBytes < 0) throw ArgumentError.value(quotaBytes, 'quotaBytes');
  }

  /// The user's contribution limit.
  final int quotaBytes;

  /// Bytes of committed objects (for example `FileStore.usedBytes`).
  final Future<int> Function() storedBytes;

  /// Real free space on the device, or null where it is not available.
  final Future<int?> Function()? freeDiskBytes;

  /// Free space to leave for the OS and other apps.
  final int safetyMarginBytes;
  final Duration reservationTtl;
  final DateTime Function() _clock;

  final Map<String, _Reservation> _reservations = {};
  Future<void> _tail = Future.value();

  /// Runs [body] after every earlier critical section has finished.
  Future<T> _exclusive<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    // The chain must continue even if [body] throws.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _purgeExpired() {
    final now = _clock();
    _reservations.removeWhere((_, r) => !r.expiresAt.isAfter(now));
  }

  int get _reservedTotal =>
      _reservations.values.fold(0, (sum, r) => sum + r.bytes);

  @override
  Future<bool> tryReserve(String reservationId, int bytes) {
    if (bytes <= 0) throw ArgumentError.value(bytes, 'bytes', 'must be positive');
    return _exclusive(() async {
      _purgeExpired();
      // Re-reserving the same id (a retry) replaces it instead of adding up.
      final previous = _reservations.remove(reservationId);
      final stored = await storedBytes();
      final fits = await _fits(stored: stored, extra: bytes);
      if (!fits) {
        if (previous != null) _reservations[reservationId] = previous;
        return false;
      }
      _reservations[reservationId] =
          _Reservation(bytes, _clock().add(reservationTtl));
      return true;
    });
  }

  @override
  Future<void> release(String reservationId) =>
      _exclusive(() async => _reservations.remove(reservationId));

  /// Final check just before the atomic move into the object store: the
  /// reservation must still be held, and the numbers must still add up, since
  /// other files may have arrived since the reservation was made.
  @override
  Future<bool> canCommit(String reservationId) => _exclusive(() async {
        _purgeExpired();
        if (!_reservations.containsKey(reservationId)) return false;
        final stored = await storedBytes();
        return _fits(stored: stored, extra: 0);
      });

  @override
  Future<int> get reservedBytes => _exclusive(() async {
        _purgeExpired();
        return _reservedTotal;
      });

  /// Whether [extra] more reserved bytes fit on top of what is stored and
  /// reserved. Must run inside [_exclusive].
  Future<bool> _fits({required int stored, required int extra}) async {
    final reserved = _reservedTotal + extra;
    if (stored + reserved > quotaBytes) return false;
    final free = await freeDiskBytes?.call();
    if (free != null && free - reserved < safetyMarginBytes) return false;
    return true;
  }
}

class _Reservation {
  const _Reservation(this.bytes, this.expiresAt);
  final int bytes;
  final DateTime expiresAt;
}
