import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:hivenet_core/hivenet_core.dart';

/// mDNS advertise and browse for `_hivenet._tcp` using `bonsoir`.
///
/// Verified on two physical Android phones on a phone hotspot. It does not work
/// on networks that filter multicast (the campus Wi-Fi), so pairing never
/// depends on it: the QR code carries the address.
///
/// The advertisement holds only public facts (id, name, port). Discovery is not
/// authentication; every connection still has to pass the secure handshake.
class BonsoirPeerDiscovery implements PeerDiscovery {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final StreamController<DiscoveryEvent> _events = StreamController.broadcast();

  /// Service name -> node id, so a "lost" event can name the node.
  final Map<String, String> _nodeByService = {};

  @override
  Stream<DiscoveryEvent> get events => _events.stream;

  @override
  Future<void> start(ServiceAdvertisement advertisement) async {
    await stop();
    const type = '_hivenet._tcp';
    final suffix = advertisement.nodeId.substring(advertisement.nodeId.length - 8);
    final service = BonsoirService(
      name: 'hivenet-$suffix',
      type: type,
      port: advertisement.port,
      attributes: {
        'nodeId': advertisement.nodeId,
        'v': '${advertisement.protocolVersion}',
        'dn': advertisement.deviceName,
      },
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();

    final discovery = BonsoirDiscovery(type: type);
    _discovery = discovery;
    await discovery.initialize();
    _sub = discovery.eventStream!.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          event.service.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent():
          final s = event.service;
          final id = s.attributes['nodeId'];
          if (id == null || id == advertisement.nodeId) return; // not ourselves
          final v4 = [for (final a in s.hostAddresses) if (!a.contains(':')) a];
          if (v4.isEmpty) return;
          _nodeByService[s.name] = id;
          _events.add(PeerFound(DiscoveredPeer(
            nodeId: id,
            deviceName: s.attributes['dn'] ?? 'HiveNet device',
            addresses: v4,
            port: s.port,
            protocolVersion: int.tryParse(s.attributes['v'] ?? '') ?? 0,
          )));
        case BonsoirDiscoveryServiceLostEvent():
          final id = _nodeByService.remove(event.service.name);
          if (id != null) _events.add(PeerLost(id));
        default:
          break;
      }
    }, onError: (Object _) {});
    await discovery.start();
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
    _nodeByService.clear();
  }
}
