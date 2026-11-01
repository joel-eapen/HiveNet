import '../../shared/models/enums.dart';
import '../../shared/models/peer_telemetry.dart';
import '../../shared/models/protocol_constants.dart';
import '../networking/network_config.dart';
import 'storage_router.dart';

/// Why a peer was removed from consideration. A peer can have several.
enum IneligibleReason {
  excluded,
  notTrusted,
  notOnline,
  staleTelemetry,
  incompatibleProtocol,
  overloaded,
  insufficientStorage,
}

/// Hard constraints (PRD FR-05). These are never relaxed by scoring or by a
/// decision model.
class EligibilityPolicy {
  const EligibilityPolicy({
    this.maxTelemetryAge = const Duration(seconds: 15),
    this.maxActiveTransfers = 2,
    this.safetyMarginBytes = 64 * 1024 * 1024,
    this.protocolVersion = kProtocolVersion,
  });

  /// Telemetry older than this is an estimate too old to rely on. Defaults to
  /// the offline timeout in [NetworkConfig].
  final Duration maxTelemetryAge;

  /// A peer already running this many transfers is skipped (PRD section 9:
  /// no more than two concurrent uploads per peer).
  final int maxActiveTransfers;

  /// Free space that must remain after the object is stored, so a peer never
  /// fills its disk to the last byte.
  final int safetyMarginBytes;
  final int protocolVersion;

  /// Policy matching a [NetworkConfig].
  factory EligibilityPolicy.fromNetwork(NetworkConfig config,
          {int safetyMarginBytes = 64 * 1024 * 1024}) =>
      EligibilityPolicy(
        maxTelemetryAge: config.offlineTimeout,
        maxActiveTransfers: config.maxConcurrentUploadsPerPeer,
        safetyMarginBytes: safetyMarginBytes,
        protocolVersion: config.protocolVersion,
      );
}

class EligibilityResult {
  const EligibilityResult({required this.eligible, required this.rejected});

  final List<PeerTelemetry> eligible;

  /// nodeId -> every reason it was rejected.
  final Map<String, Set<IneligibleReason>> rejected;
}

/// Pure function of its inputs: no I/O, no clock of its own.
///
/// Passing the filter means a peer is *worth asking*. The destination still
/// validates its own capacity before accepting a write (PRD FR-02), because
/// telemetry is only an estimate.
EligibilityResult filterEligible({
  required PlacementRequest request,
  required List<PeerTelemetry> candidates,
  required Set<String> trustedNodeIds,
  required DateTime now,
  EligibilityPolicy policy = const EligibilityPolicy(),
}) {
  final eligible = <PeerTelemetry>[];
  final rejected = <String, Set<IneligibleReason>>{};

  for (final peer in candidates) {
    final reasons = <IneligibleReason>{};

    if (request.excludeNodeIds.contains(peer.nodeId)) {
      reasons.add(IneligibleReason.excluded);
    }
    if (!trustedNodeIds.contains(peer.nodeId)) {
      reasons.add(IneligibleReason.notTrusted);
    }
    if (peer.status != PeerStatus.online) {
      reasons.add(IneligibleReason.notOnline);
    }
    if (now.difference(peer.lastSeen) > policy.maxTelemetryAge) {
      reasons.add(IneligibleReason.staleTelemetry);
    }
    if (peer.protocolVersion != policy.protocolVersion) {
      reasons.add(IneligibleReason.incompatibleProtocol);
    }
    if (peer.activeTransfers >= policy.maxActiveTransfers) {
      reasons.add(IneligibleReason.overloaded);
    }
    final free = peer.availableStorageBytes - peer.reservedStorageBytes;
    if (free - policy.safetyMarginBytes < request.sizeBytes) {
      reasons.add(IneligibleReason.insufficientStorage);
    }

    if (reasons.isEmpty) {
      eligible.add(peer);
    } else {
      rejected[peer.nodeId] = reasons;
    }
  }
  return EligibilityResult(eligible: eligible, rejected: rejected);
}
