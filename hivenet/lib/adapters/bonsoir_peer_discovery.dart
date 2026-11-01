import 'package:hivenet_core/hivenet_core.dart';

/// Will wrap `bonsoir` for mDNS on `_hivenet._tcp` (PRD FR-01, Milestone 2).
///
/// Not implemented yet. Needs physical-device validation of iOS Bonjour
/// declarations and Android multicast behaviour first (PRD section 10.2).
class BonsoirPeerDiscovery implements PeerDiscovery {
  const BonsoirPeerDiscovery();

  @override
  Stream<DiscoveryEvent> get events => const Stream.empty();

  @override
  Future<void> start(ServiceAdvertisement advertisement) =>
      throw UnimplementedError('BonsoirPeerDiscovery: Milestone 2');

  @override
  Future<void> stop() async {}
}
