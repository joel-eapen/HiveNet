import '../../shared/models/protocol_constants.dart';

/// Networking constants from PRD §5.3, §5.4 and §9. Starting values to be
/// tuned on real devices.
class NetworkConfig {
  const NetworkConfig({
    this.serviceType = '_hivenet._tcp',
    this.heartbeatInterval = const Duration(seconds: 5),
    this.offlineTimeout = const Duration(seconds: 15),
    this.chunkSizeBytes = 1024 * 1024,
    this.maxConcurrentUploadsPerPeer = 2,
    this.maxFrameBytes = 4 * 1024 * 1024,
    this.protocolVersion = kProtocolVersion,
  });

  /// mDNS service type. Do not put secrets in the advertisement.
  final String serviceType;
  final Duration heartbeatInterval;

  /// Silence after which a peer is marked offline (three missed heartbeats).
  final Duration offlineTimeout;

  /// 1 MiB.
  final int chunkSizeBytes;
  final int maxConcurrentUploadsPerPeer;

  /// Upper bound for one framed message; larger frames are rejected.
  final int maxFrameBytes;
  final int protocolVersion;
}
