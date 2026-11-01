import '../../shared/models/manifest_event.dart';

class ReconciliationResult {
  const ReconciliationResult({required this.toApply, required this.toSend});

  /// Remote events this device should apply.
  final List<ManifestEvent> toApply;

  /// Local events the remote is missing.
  final List<ManifestEvent> toSend;
}

/// Deterministic reconciliation by per-owner version, with tombstones. Wall
/// clocks must not decide ordering. No CRDT or consensus in the MVP.
abstract interface class Reconciler {
  ReconciliationResult reconcile({
    required List<ManifestEvent> local,
    required List<ManifestEvent> remote,
  });
}

class UnimplementedReconciler implements Reconciler {
  const UnimplementedReconciler();

  @override
  ReconciliationResult reconcile({
    required List<ManifestEvent> local,
    required List<ManifestEvent> remote,
  }) =>
      throw UnimplementedError('Reconciler: Milestone 5');
}
