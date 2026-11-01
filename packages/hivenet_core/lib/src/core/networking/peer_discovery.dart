/// What a device advertises over mDNS (PRD §5.4). Never include secrets,
/// tokens or keys. Discovery is not authentication.
class ServiceAdvertisement {
  const ServiceAdvertisement({
    required this.nodeId,
    required this.deviceName,
    required this.port,
    required this.protocolVersion,
  });

  final String nodeId;
  final String deviceName;
  final int port;
  final int protocolVersion;
}

/// A peer seen on the local network but not necessarily trusted.
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.nodeId,
    required this.deviceName,
    required this.addresses,
    required this.port,
    required this.protocolVersion,
  });

  final String nodeId;
  final String deviceName;
  final List<String> addresses;
  final int port;
  final int protocolVersion;
}

sealed class DiscoveryEvent {
  const DiscoveryEvent();
}

class PeerFound extends DiscoveryEvent {
  const PeerFound(this.peer);
  final DiscoveredPeer peer;
}

class PeerLost extends DiscoveryEvent {
  const PeerLost(this.nodeId);
  final String nodeId;
}

/// mDNS discovery (PRD FR-01). Implemented in the app with `bonsoir`.
/// Must handle denied local-network permission, Wi-Fi changes and networks
/// with client isolation.
abstract interface class PeerDiscovery {
  Stream<DiscoveryEvent> get events;
  Future<void> start(ServiceAdvertisement advertisement);
  Future<void> stop();
}

class UnimplementedPeerDiscovery implements PeerDiscovery {
  const UnimplementedPeerDiscovery();

  @override
  Stream<DiscoveryEvent> get events => const Stream.empty();

  @override
  Future<void> start(ServiceAdvertisement advertisement) =>
      throw UnimplementedError('PeerDiscovery: Milestone 2');

  @override
  Future<void> stop() async {}
}
