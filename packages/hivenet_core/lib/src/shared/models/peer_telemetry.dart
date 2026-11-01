import '../utils/json_helpers.dart';
import 'enums.dart';

/// Authenticated peer telemetry (PRD FR-02). Treat as an estimate: a storage
/// peer must re-validate capacity itself before accepting a write.
class PeerTelemetry {
  const PeerTelemetry({
    required this.nodeId,
    required this.deviceName,
    required this.protocolVersion,
    required this.ipAddresses,
    required this.port,
    required this.availableStorageBytes,
    required this.totalStorageBytes,
    required this.reservedStorageBytes,
    required this.activeTransfers,
    required this.lastSeen,
    required this.status,
    this.measuredLatencyMs,
    this.bandwidthEstimate,
    this.reliabilityScore = 0,
  });

  final String nodeId;
  final String deviceName;
  final int protocolVersion;
  final List<String> ipAddresses;
  final int port;
  final int availableStorageBytes;
  final int totalStorageBytes;
  final int reservedStorageBytes;
  final int activeTransfers;
  final DateTime lastSeen;
  final PeerStatus status;
  final int? measuredLatencyMs;

  /// Estimated throughput in bytes per second.
  final int? bandwidthEstimate;

  /// 0..100.
  final double reliabilityScore;

  Json toJson() => {
        'nodeId': nodeId,
        'deviceName': deviceName,
        'protocolVersion': protocolVersion,
        'ipAddresses': ipAddresses,
        'port': port,
        'availableStorageBytes': availableStorageBytes,
        'totalStorageBytes': totalStorageBytes,
        'reservedStorageBytes': reservedStorageBytes,
        'activeTransfers': activeTransfers,
        'lastSeen': dateToJson(lastSeen),
        'status': status.wire,
        'measuredLatencyMs': measuredLatencyMs,
        'bandwidthEstimate': bandwidthEstimate,
        'reliabilityScore': reliabilityScore,
      };

  factory PeerTelemetry.fromJson(Json json) => PeerTelemetry(
        nodeId: json['nodeId']! as String,
        deviceName: json['deviceName']! as String,
        protocolVersion: json['protocolVersion']! as int,
        ipAddresses: (json['ipAddresses']! as List).cast<String>(),
        port: json['port']! as int,
        availableStorageBytes: json['availableStorageBytes']! as int,
        totalStorageBytes: json['totalStorageBytes']! as int,
        reservedStorageBytes: json['reservedStorageBytes']! as int,
        activeTransfers: json['activeTransfers']! as int,
        lastSeen: dateFromJson(json['lastSeen']),
        status: enumFromWire(PeerStatus.values, json['status']! as String),
        measuredLatencyMs: json['measuredLatencyMs'] as int?,
        bandwidthEstimate: json['bandwidthEstimate'] as int?,
        reliabilityScore: (json['reliabilityScore'] as num? ?? 0).toDouble(),
      );
}
