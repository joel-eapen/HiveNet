import '../utils/json_helpers.dart';
import 'enums.dart';

/// Typed backend error. The frontend maps [code] to user-facing text and keeps
/// [technicalDetails] for advanced views only.
class HiveError implements Exception {
  const HiveError({
    required this.code,
    required this.message,
    this.isRetryable = false,
    this.technicalDetails,
  });

  final HiveErrorCode code;
  final String message;
  final bool isRetryable;
  final String? technicalDetails;

  Json toJson() => {
        'code': code.wire,
        'message': message,
        'isRetryable': isRetryable,
        'technicalDetails': technicalDetails,
      };

  factory HiveError.fromJson(Json json) => HiveError(
        code: enumFromWire(HiveErrorCode.values, json['code']! as String),
        message: json['message']! as String,
        isRetryable: json['isRetryable'] as bool? ?? false,
        technicalDetails: json['technicalDetails'] as String?,
      );

  @override
  String toString() => 'HiveError(${code.wire}): $message';
}
