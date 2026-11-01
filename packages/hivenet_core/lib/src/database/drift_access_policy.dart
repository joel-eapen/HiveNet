import 'package:drift/drift.dart';

import '../shared/models/enums.dart';
import '../shared/models/security_models.dart';
import 'app_database.dart';

/// Who may do what to which image, on this device (PRD FR-09A).
///
/// Store, retrieve and view are separate permissions: holding one never
/// implies another. The owner is recorded as holding every permission for an
/// image they uploaded; everyone else needs an explicit grant.
///
/// Grants here are local records. Owner-signed, device-bound grants that
/// travel between devices (so a storage peer can honour them while the owner
/// is offline) are the next step; the signature column stays empty until then.
class DriftAccessPolicy {
  DriftAccessPolicy(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Records that [ownerNodeId] owns [contentId]: the right to retrieve it.
  /// Safe to call again; it never overwrites an existing, possibly revoked row.
  Future<void> recordOwner(String contentId, String ownerNodeId) async {
    final existing = await _row(contentId, ownerNodeId, PermissionType.retrieve);
    if (existing != null) return;
    await grant(
      contentId: contentId,
      granteeNodeId: ownerNodeId,
      permission: PermissionType.retrieve,
      grantedBy: ownerNodeId,
    );
  }

  /// True if [nodeId] uploaded [contentId] (it granted itself the right to
  /// retrieve it). Only the owner may change who else has access.
  Future<bool> isOwner(String nodeId, String contentId) async {
    final row = await _row(contentId, nodeId, PermissionType.retrieve);
    return row != null && row.grantedBy == nodeId && row.revokedAt == null;
  }

  /// True only for an active (not revoked, not expired) grant to [requester]
  /// for exactly this permission.
  Future<bool> isAllowed(
    String requesterNodeId,
    String contentId,
    PermissionType permission,
  ) async {
    final row = await _row(contentId, requesterNodeId, permission);
    if (row == null || row.revokedAt != null) return false;
    final expires = row.expiresAt;
    return expires == null || _clock().isBefore(expires);
  }

  Future<void> grant({
    required String contentId,
    required String granteeNodeId,
    required PermissionType permission,
    required String grantedBy,
    DateTime? expiresAt,
  }) async {
    final previous = await _row(contentId, granteeNodeId, permission);
    await _db.accessGrantsDao.upsert(AccessGrantsCompanion.insert(
      contentId: contentId,
      granteeNodeId: granteeNodeId,
      permission: permission.wire,
      grantedBy: grantedBy,
      grantVersion: (previous?.grantVersion ?? 0) + 1,
      createdAt: _clock().toUtc(),
      expiresAt: Value(expiresAt),
    ));
  }

  /// Revokes future access. It cannot take back anything already downloaded.
  Future<void> revoke(String contentId, String granteeNodeId, PermissionType permission) async {
    final row = await _row(contentId, granteeNodeId, permission);
    if (row == null || row.revokedAt != null) return;
    await _db.accessGrantsDao.upsert(AccessGrantsCompanion.insert(
      contentId: row.contentId,
      granteeNodeId: row.granteeNodeId,
      permission: row.permission,
      grantedBy: row.grantedBy,
      grantVersion: row.grantVersion + 1,
      createdAt: row.createdAt,
      keyVersion: Value(row.keyVersion),
      expiresAt: Value(row.expiresAt),
      revokedAt: Value(_clock().toUtc()),
      signature: Value(row.signature),
    ));
  }

  Future<List<AccessGrant>> grantsFor(String contentId) async {
    final rows = await _db.accessGrantsDao.forContent(contentId);
    return [
      for (final r in rows)
        AccessGrant(
          contentId: r.contentId,
          granteeNodeId: r.granteeNodeId,
          permission: enumFromWire(PermissionType.values, r.permission),
          grantedBy: r.grantedBy,
          grantVersion: r.grantVersion,
          keyVersion: r.keyVersion,
          createdAt: r.createdAt.toUtc(),
          expiresAt: r.expiresAt?.toUtc(),
          revokedAt: r.revokedAt?.toUtc(),
          signature: r.signature,
        ),
    ];
  }

  Future<AccessGrantRow?> _row(String contentId, String grantee, PermissionType p) async {
    final rows = await _db.accessGrantsDao.forContent(contentId);
    for (final r in rows) {
      if (r.granteeNodeId == grantee && r.permission == p.wire) return r;
    }
    return null;
  }
}
