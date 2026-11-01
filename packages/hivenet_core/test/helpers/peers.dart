import 'package:hivenet_core/hivenet_core.dart';

final DateTime testNow = DateTime.utc(2026, 11, 1, 12);
const int gib = 1024 * 1024 * 1024;

/// A healthy, trusted-looking peer by default; override what a test cares about.
PeerTelemetry peer(
  String id, {
  PeerStatus status = PeerStatus.online,
  int total = 20 * gib,
  int available = 10 * gib,
  int reserved = 0,
  int activeTransfers = 0,
  int protocolVersion = kProtocolVersion,
  Duration age = const Duration(seconds: 2),
  int? latencyMs = 20,
  int? bandwidth = 12500000,
  double? reliability = 90,
  int? battery,
  bool? charging,
  int? uptimeSeconds,
}) =>
    PeerTelemetry(
      nodeId: id,
      deviceName: id,
      protocolVersion: protocolVersion,
      ipAddresses: const ['192.168.1.2'],
      port: 45678,
      availableStorageBytes: available,
      totalStorageBytes: total,
      reservedStorageBytes: reserved,
      activeTransfers: activeTransfers,
      lastSeen: testNow.subtract(age),
      status: status,
      measuredLatencyMs: latencyMs,
      bandwidthEstimate: bandwidth,
      reliabilityScore: reliability,
      batteryPercent: battery,
      isCharging: charging,
      uptimeSeconds: uptimeSeconds,
    );
