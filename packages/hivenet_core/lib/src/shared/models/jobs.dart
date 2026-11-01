import '../utils/json_helpers.dart';
import 'enums.dart';

/// Persisted upload transaction (PRD §6.4, §13.1).
class UploadJob {
  const UploadJob({
    required this.jobId,
    required this.status,
    required this.requestedReplicationFactor,
    required this.createdAt,
    this.contentId,
    this.completedAt,
    this.failureReason,
  });

  final String jobId;

  /// Known only after compression and hashing.
  final String? contentId;
  final UploadState status;
  final int requestedReplicationFactor;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? failureReason;

  /// Returns a copy in [next], throwing if the state machine forbids it.
  UploadJob transitionTo(UploadState next, {String? failureReason}) {
    if (!status.canTransitionTo(next)) {
      throw StateError('Illegal upload transition ${status.wire} -> ${next.wire}');
    }
    return UploadJob(
      jobId: jobId,
      contentId: contentId,
      status: next,
      requestedReplicationFactor: requestedReplicationFactor,
      createdAt: createdAt,
      completedAt: next == UploadState.completed ? DateTime.now().toUtc() : completedAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  Json toJson() => {
        'jobId': jobId,
        'contentId': contentId,
        'status': status.wire,
        'requestedReplicationFactor': requestedReplicationFactor,
        'createdAt': dateToJson(createdAt),
        'completedAt': optionalDateToJson(completedAt),
        'failureReason': failureReason,
      };

  factory UploadJob.fromJson(Json json) => UploadJob(
        jobId: json['jobId']! as String,
        contentId: json['contentId'] as String?,
        status: enumFromWire(UploadState.values, json['status']! as String),
        requestedReplicationFactor: json['requestedReplicationFactor']! as int,
        createdAt: dateFromJson(json['createdAt']),
        completedAt: optionalDateFromJson(json['completedAt']),
        failureReason: json['failureReason'] as String?,
      );
}

/// One chunked transfer between two nodes (PRD §6.5).
class TransferRecord {
  const TransferRecord({
    required this.transferId,
    required this.contentId,
    required this.sourceNodeId,
    required this.destinationNodeId,
    required this.direction,
    required this.status,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.startedAt,
    required this.updatedAt,
  });

  final String transferId;
  final String contentId;
  final String sourceNodeId;
  final String destinationNodeId;
  final TransferDirection direction;
  final TransferStatus status;
  final int bytesTransferred;
  final int totalBytes;
  final DateTime startedAt;
  final DateTime updatedAt;

  double get progress =>
      totalBytes == 0 ? 0 : (bytesTransferred / totalBytes).clamp(0, 1);

  Json toJson() => {
        'transferId': transferId,
        'contentId': contentId,
        'sourceNodeId': sourceNodeId,
        'destinationNodeId': destinationNodeId,
        'direction': direction.wire,
        'status': status.wire,
        'bytesTransferred': bytesTransferred,
        'totalBytes': totalBytes,
        'startedAt': dateToJson(startedAt),
        'updatedAt': dateToJson(updatedAt),
      };

  factory TransferRecord.fromJson(Json json) => TransferRecord(
        transferId: json['transferId']! as String,
        contentId: json['contentId']! as String,
        sourceNodeId: json['sourceNodeId']! as String,
        destinationNodeId: json['destinationNodeId']! as String,
        direction: enumFromWire(
            TransferDirection.values, json['direction']! as String),
        status: enumFromWire(TransferStatus.values, json['status']! as String),
        bytesTransferred: json['bytesTransferred']! as int,
        totalBytes: json['totalBytes']! as int,
        startedAt: dateFromJson(json['startedAt']),
        updatedAt: dateFromJson(json['updatedAt']),
      );
}
