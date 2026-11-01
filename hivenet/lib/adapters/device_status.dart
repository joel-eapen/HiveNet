import 'package:flutter/services.dart';

/// This phone's battery, reported to peers deciding whether to store a copy
/// here. Read through a small Android platform channel (see `MainActivity.kt`).
///
/// Both values are best effort: null means "unknown", which peers treat as
/// neutral rather than as a problem.
class DeviceStatus {
  DeviceStatus({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('hivenet/device_status');

  final MethodChannel _channel;

  /// `(percent, charging)`, either of which may be null.
  Future<({int? percent, bool? charging})> battery() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('battery');
      if (result == null) return (percent: null, charging: null);
      final percent = result['percent'];
      final charging = result['charging'];
      return (
        percent: percent is int ? percent.clamp(0, 100) : null,
        charging: charging is bool ? charging : null,
      );
    } on PlatformException {
      return (percent: null, charging: null);
    } on MissingPluginException {
      // Not running on Android (tests, previews).
      return (percent: null, charging: null);
    }
  }
}
