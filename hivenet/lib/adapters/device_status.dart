import 'package:battery_plus/battery_plus.dart';

/// This phone's battery, as reported to peers that are deciding whether to
/// store a copy here. Both values are best effort: null means "unknown", which
/// peers treat as neutral rather than as a problem.
class DeviceStatus {
  DeviceStatus([Battery? battery]) : _battery = battery ?? Battery();

  final Battery _battery;

  Future<int?> batteryPercent() async {
    try {
      final level = await _battery.batteryLevel;
      return level < 0 ? null : level.clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  /// True when plugged in (charging or full on the charger).
  Future<bool?> isCharging() async {
    try {
      final state = await _battery.batteryState;
      return switch (state) {
        BatteryState.charging || BatteryState.full || BatteryState.connectedNotCharging => true,
        BatteryState.discharging => false,
        BatteryState.unknown => null,
      };
    } catch (_) {
      return null;
    }
  }
}
