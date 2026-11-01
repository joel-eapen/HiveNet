import 'dart:typed_data';

import '../../shared/models/enums.dart';

/// Public identity of this installation. Never contains the private key.
class DeviceIdentity {
  const DeviceIdentity({
    required this.nodeId,
    required this.deviceName,
    required this.platform,
    required this.publicKey,
    required this.fingerprint,
    required this.createdAt,
  });

  final String nodeId;
  final String deviceName;
  final DevicePlatform platform;
  final Uint8List publicKey;
  final String fingerprint;
  final DateTime createdAt;
}

/// Creates and loads the persistent device identity (PRD FR-01). The private
/// key stays in the [KeyStore]; signing happens inside this service.
abstract interface class DeviceIdentityService {
  /// Returns the existing identity or creates one on first launch.
  Future<DeviceIdentity> loadOrCreate({required String deviceName});

  /// Signs with the device private key (grants, manifest events, pairing).
  Future<Uint8List> sign(Uint8List message);

  Future<bool> verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  });
}

class UnimplementedDeviceIdentityService implements DeviceIdentityService {
  const UnimplementedDeviceIdentityService();

  @override
  Future<DeviceIdentity> loadOrCreate({required String deviceName}) =>
      throw UnimplementedError('DeviceIdentityService: Milestone 1');

  @override
  Future<Uint8List> sign(Uint8List message) =>
      throw UnimplementedError('DeviceIdentityService: Milestone 1');

  @override
  Future<bool> verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) =>
      throw UnimplementedError('DeviceIdentityService: Milestone 1');
}
