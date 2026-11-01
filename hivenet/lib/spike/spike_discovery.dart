// THROWAWAY Milestone 0 spike code.
import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

class FoundPeer {
  FoundPeer({
    required this.serviceName,
    required this.nodeId,
    required this.platform,
    required this.host,
    required this.port,
  });

  final String serviceName;
  final String nodeId;
  final String platform;
  final String host;
  final int port;
}

/// mDNS advertise + browse on `_hivenet._tcp` via bonsoir. No secrets in the
/// advertisement (PRD section 5.4).
class SpikeDiscovery {
  static const serviceType = '_hivenet._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  bool get running => _discovery != null;

  Future<void> start({
    required String nodeId,
    required String deviceName,
    required String platform,
    required int port,
    required void Function(FoundPeer peer) onFound,
    required void Function(String serviceName) onLost,
    required void Function(String message) log,
  }) async {
    final service = BonsoirService(
      name: 'hivenet-${nodeId.substring(nodeId.length - 8)}',
      type: serviceType,
      port: port,
      attributes: {'nodeId': nodeId, 'v': '1', 'platform': platform, 'dn': deviceName},
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();
    log('mDNS broadcast started as ${service.name} on port $port');

    final discovery = BonsoirDiscovery(type: serviceType);
    _discovery = discovery;
    await discovery.initialize();
    _sub = discovery.eventStream!.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          final s = event.service;
          log('mDNS found ${s.name}, resolving');
          s.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent():
          final s = event.service;
          final peerId = s.attributes['nodeId'];
          if (peerId == null || peerId == nodeId) return; // ignore ourselves
          final v4 = s.hostAddresses.where((a) => !a.contains(':')).toList();
          final host = v4.isNotEmpty ? v4.first : (s.hostAddresses.isNotEmpty ? s.hostAddresses.first : null);
          if (host == null) {
            log('mDNS resolved ${s.name} but no address');
            return;
          }
          onFound(FoundPeer(
            serviceName: s.name,
            nodeId: peerId,
            platform: s.attributes['platform'] ?? 'unknown',
            host: host,
            port: s.port,
          ));
        case BonsoirDiscoveryServiceLostEvent():
          log('mDNS lost ${event.service.name}');
          onLost(event.service.name);
        case BonsoirDiscoveryServiceResolveFailedEvent():
          log('mDNS resolve failed');
        default:
          break;
      }
    }, onError: (Object e) => log('mDNS error: $e'));
    await discovery.start();
    log('mDNS discovery started for $serviceType');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
  }
}
