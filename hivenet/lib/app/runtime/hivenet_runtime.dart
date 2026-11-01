import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../adapters/app_paths.dart';
import '../../adapters/bonsoir_peer_discovery.dart';
import '../../adapters/flutter_image_compressor.dart';

/// A device as the UI sees it.
class PeerView {
  PeerView({
    required this.nodeId,
    required this.name,
    required this.status,
    required this.paired,
    this.host,
    this.port,
    this.telemetry,
    this.lastSeen,
  });

  final String nodeId;
  final String name;
  PeerStatus status;
  final bool paired;
  String? host;
  int? port;
  PeerTelemetry? telemetry;
  DateTime? lastSeen;
}

class StorageStats {
  const StorageStats({
    required this.replicaBytes,
    required this.replicaCount,
    required this.reservedBytes,
    required this.quotaBytes,
    required this.ownedBytes,
    required this.cacheBytes,
    required this.partialBytes,
  });

  /// Encrypted copies this phone stores for others (and for itself).
  final int replicaBytes;
  final int replicaCount;
  final int reservedBytes;
  final int quotaBytes;

  /// Encrypted originals of images this phone uploaded.
  final int ownedBytes;

  /// Decrypted images kept so they open instantly. Can be cleared.
  final int cacheBytes;

  /// Unfinished transfers.
  final int partialBytes;
}

/// A pairing waiting for the user to compare fingerprints and accept.
class PairingPrompt {
  PairingPrompt(this.peerName, this.fingerprint) : _answer = Completer<bool>();
  final String peerName;
  final String fingerprint;
  final Completer<bool> _answer;
  Future<bool> get answer => _answer.future;
  void respond(bool accepted) {
    if (!_answer.isCompleted) _answer.complete(accepted);
  }
}

/// How the last pairing attempt on this device ended, for the UI to show.
class PairingOutcome {
  const PairingOutcome.success(this.message) : ok = true;
  const PairingOutcome.failure(this.message) : ok = false;
  final bool ok;
  final String message;
}

/// Everything HiveNet does on this device, in one place.
///
/// The UI talks only to this class. It owns the device identity, the listening
/// server, discovery, the list of paired devices, and the upload, retrieval and
/// sharing services, all built from the tested core package.
///
/// Foreground-first (PRD section 10.1): the server runs while the app process
/// does; a backgrounded phone simply stops answering and is shown unavailable.
class HiveNetRuntime {
  HiveNetRuntime._(this.paths, this.db, this.keys, this.deviceName);

  final AppPaths paths;
  final AppDatabase db;
  final KeyStore keys;
  String deviceName;

  late final Ed25519DeviceIdentityService _signer;
  late final DeviceIdentity identity;
  late final PeerServer _server;
  late final PeerStorageService _storage;
  late final DriftAccessPolicy policy;
  late final LocalManifestRepository manifests;
  late final DriftReplicationStore _replicationStore;
  late final LocalQuotaManager quota;
  late final UploadService _uploads;
  late final RetrievalService _retrieval;
  late final LocalFileStore files;
  final PeerDiscovery _discovery = BonsoirPeerDiscovery();
  final ImageCompressor _compressor = const FlutterImageCompressor();

  final Map<String, PeerView> _peers = {};
  final _peerChanges = StreamController<List<PeerView>>.broadcast();
  final Map<String, int> _failures = {};
  Timer? _probeTimer;
  StreamSubscription<DiscoveryEvent>? _discoverySub;
  PairingInviteState? _invite;

  /// Set while a pairing needs the user's decision; the UI shows a dialog.
  final ValueNotifier<PairingPrompt?> pendingPairing = ValueNotifier(null);

  /// Set when a pairing that another phone started with our code finishes or
  /// fails, so the screen showing the code can say what happened.
  final ValueNotifier<PairingOutcome?> lastPairing = ValueNotifier(null);

  int get port => _server.port;

  /// Contribution limit. A placeholder until the Storage screen sets it.
  static const int contributionBytes = 1024 * 1024 * 1024;

  static Future<HiveNetRuntime> start({
    required AppPaths paths,
    required AppDatabase db,
    required KeyStore keys,
    required DevicePlatform platform,
    String deviceName = 'My phone',
  }) async {
    final rt = HiveNetRuntime._(paths, db, keys, deviceName);
    await rt._init(platform);
    return rt;
  }

  Future<void> _init(DevicePlatform platform) async {
    final layout = paths.layout;
    _signer = Ed25519DeviceIdentityService(keyStore: keys, platform: platform);
    identity = await _signer.loadOrCreate(deviceName: deviceName);

    files = LocalFileStore(layout, const Sha256IntegrityChecker());
    final chunks = FileChunkManager(layout);
    quota = LocalQuotaManager(
      quotaBytes: contributionBytes,
      storedBytes: files.usedBytes,
    );
    policy = DriftAccessPolicy(db);
    manifests = LocalManifestRepository(db);
    _replicationStore = DriftReplicationStore(db);

    _storage = PeerStorageService(
      files: files,
      chunks: chunks,
      quota: quota,
      authorizeRetrieval: (requester, contentId) =>
          policy.isAllowed(requester, contentId, PermissionType.retrieve),
      onCommitted: policy.recordOwner,
      telemetry: _telemetryReply,
      onOther: _onOtherMessage,
    );

    final transport = ChannelReplicaTransport(
      dial: dial,
      chunks: chunks,
      localNodeId: identity.nodeId,
    );
    _uploads = UploadService(
      localNodeId: identity.nodeId,
      layout: layout,
      encryption: AesGcmEncryptionService(),
      integrity: const Sha256IntegrityChecker(),
      keys: keys,
      manifests: manifests,
      router: DeterministicStorageRouter(
        trustedNodeIds: _pairedIds,
        policy: const EligibilityPolicy(),
      ),
      replication: DefaultReplicationManager(
        transport: transport,
        store: _replicationStore,
      ),
      store: _replicationStore,
      peerTelemetry: () async => [
        for (final p in _peers.values)
          if (p.paired && p.telemetry != null) p.telemetry!,
      ],
    );
    _retrieval = RetrievalService(
      localNodeId: identity.nodeId,
      layout: layout,
      dial: dial,
      chunks: chunks,
      keys: keys,
      encryption: AesGcmEncryptionService(),
      integrity: const Sha256IntegrityChecker(),
      manifests: manifests,
      replicaHolders: _holdersOf,
    );

    _server = PeerServer(
      identity: identity,
      signer: _signer,
      verifier: _verifier,
      onChannel: _onChannel,
      allowUnknown: () => _invite?.isUsable ?? false,
    );
    await _server.start();

    await _loadPairedPeers();
    _probeTimer = Timer.periodic(const Duration(seconds: 8), (_) => _probeAll());
    unawaited(_probeAll());
    unawaited(startDiscovery());
  }

  Future<void> dispose() async {
    _probeTimer?.cancel();
    await _discoverySub?.cancel();
    await _discovery.stop();
    await _server.stop();
    await _peerChanges.close();
  }

  // ------------------------------------------------------------ trust

  PeerVerifier get _verifier => trustedDeviceVerifier(_trustedDevice);

  Future<TrustedDevice?> _trustedDevice(String nodeId) async {
    final r = await db.trustedDevicesDao.byNodeId(nodeId);
    if (r == null) return null;
    return TrustedDevice(
      nodeId: r.nodeId,
      publicKey: r.publicKey,
      fingerprint: r.fingerprint,
      displayName: r.displayName,
      pairedAt: r.pairedAt.toUtc(),
      revokedAt: r.revokedAt?.toUtc(),
      trustStatus: enumFromWire(TrustStatus.values, r.trustStatus),
    );
  }

  Future<Set<String>> _pairedIds() async => {
        for (final r in await db.trustedDevicesDao.getAll())
          if (r.trustStatus == TrustStatus.paired.wire && r.revokedAt == null) r.nodeId,
      };

  Stream<List<TrustedDevice>> watchPairedDevices() =>
      db.trustedDevicesDao.watchAll().map((rows) => [
            for (final r in rows)
              TrustedDevice(
                nodeId: r.nodeId,
                publicKey: r.publicKey,
                fingerprint: r.fingerprint,
                displayName: r.displayName,
                pairedAt: r.pairedAt.toUtc(),
                revokedAt: r.revokedAt?.toUtc(),
                trustStatus: enumFromWire(TrustStatus.values, r.trustStatus),
              ),
          ]);

  Future<void> revokeDevice(String nodeId) async {
    final r = await db.trustedDevicesDao.byNodeId(nodeId);
    if (r == null) return;
    await db.trustedDevicesDao.upsert(TrustedDevicesCompanion.insert(
      nodeId: r.nodeId,
      publicKey: r.publicKey,
      fingerprint: r.fingerprint,
      displayName: r.displayName,
      pairedAt: r.pairedAt,
      trustStatus: TrustStatus.revoked.wire,
      revokedAt: Value(DateTime.now().toUtc()),
    ));
    final view = _peers[nodeId];
    if (view != null) {
      view.status = PeerStatus.offline;
      _emit();
    }
  }

  // ---------------------------------------------------------- connecting

  /// Opens an authenticated channel to a paired device, or throws.
  Future<SecureChannel> dial(String nodeId) async {
    final view = _peers[nodeId];
    final host = view?.host;
    final port = view?.port;
    if (host == null || port == null) {
      throw HiveError(
        code: HiveErrorCode.peerDisconnected,
        message: 'This device\'s address is not known yet.',
      );
    }
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    final channel = await SecureChannel.connect(
      socket,
      identity: identity,
      signer: _signer,
      verifier: _verifier,
    );
    if (channel.peerNodeId != nodeId) {
      await channel.close();
      throw HiveError(
        code: HiveErrorCode.unauthenticated,
        message: 'A different device answered at that address.',
      );
    }
    return channel;
  }

  void _onChannel(SecureChannel channel) {
    if (channel.peerTrust == PeerTrust.unknown) {
      _servePairing(channel);
      return;
    }
    // Paired devices can reach us from a new address; remember it.
    final view = _peers[channel.peerNodeId];
    if (view != null) {
      view.lastSeen = DateTime.now();
    }
    unawaited(_storage.serve(channel));
  }

  // ------------------------------------------------------------- pairing

  /// Creates a pairing code to show as a QR. Unknown devices are accepted on
  /// this device only until the code is used or expires.
  Future<PairingInvite> createInvite() async {
    final rnd = Random.secure();
    final invite = PairingInvite(
      nodeId: identity.nodeId,
      publicKey: identity.publicKey,
      host: await _localAddress(),
      port: _server.port,
      secret: Uint8List.fromList(List.generate(PairingInvite.secretBytes, (_) => rnd.nextInt(256))),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      deviceName: deviceName,
    );
    lastPairing.value = null;
    _invite = PairingInviteState(invite: invite);
    return invite;
  }

  void cancelInvite() => _invite = null;

  void _servePairing(SecureChannel channel) {
    final state = _invite;
    if (state == null || !state.isUsable) {
      channel.close();
      return;
    }
    int? peerPort;
    runPairingAsInviter(
      channel: channel,
      state: state,
      self: identity,
      confirm: _askUser,
      save: _saveTrusted,
      onPeerPort: (p) => peerPort = p,
    ).then((device) async {
      _invite = null;
      await _rememberAddress(device.nodeId, device.displayName, channel.remoteAddress, peerPort);
      lastPairing.value = PairingOutcome.success('Paired with ${device.displayName}');
    }).catchError((Object e) {
      // Declined, wrong code, or dropped. Nothing was saved; say so.
      debugPrint('pairing (inviter) failed: $e');
      lastPairing.value = PairingOutcome.failure(_pairingFailureText(e));
    });
  }

  String _pairingFailureText(Object e) {
    final detail = e is HiveError ? (e.technicalDetails ?? '') : '$e';
    if (detail.contains('declined')) return 'Pairing was declined.';
    if (detail.contains('invalid, used or expired')) {
      return 'The other phone used a code that is no longer valid. Make a new code.';
    }
    if (detail.contains('timed out')) return 'Pairing timed out. Try again.';
    return 'Pairing did not complete. No device was added.';
  }

  /// Pairs with the device that showed [qrText]. Throws if the code is invalid,
  /// the other device is not the one in the code, or either user declines.
  Future<TrustedDevice> pairWithCode(String qrText) async {
    final invite = PairingInvite.parse(qrText, now: DateTime.now().toUtc());
    final socket = await Socket.connect(invite.host, invite.port,
        timeout: const Duration(seconds: 8));
    final channel = await SecureChannel.connect(
      socket,
      identity: identity,
      signer: _signer,
      verifier: _verifier,
      allowUnknown: true,
      expectedPeerKey: invite.publicKey, // the code pins who we must be talking to
    );
    final device = await runPairingAsJoiner(
      channel: channel,
      invite: invite,
      self: identity,
      confirm: _askUser,
      save: _saveTrusted,
      listenPort: _server.port,
    );
    await _rememberAddress(device.nodeId, device.displayName, invite.host, invite.port);
    return device;
  }

  Future<bool> _askUser(String name, String fingerprint) {
    final prompt = PairingPrompt(name, fingerprint);
    pendingPairing.value = prompt;
    return prompt.answer.timeout(const Duration(minutes: 2), onTimeout: () => false).whenComplete(() {
      if (pendingPairing.value == prompt) pendingPairing.value = null;
    });
  }

  Future<void> _saveTrusted(TrustedDevice d) =>
      db.trustedDevicesDao.upsert(TrustedDevicesCompanion.insert(
        nodeId: d.nodeId,
        publicKey: d.publicKey,
        fingerprint: d.fingerprint,
        displayName: d.displayName,
        pairedAt: d.pairedAt,
        trustStatus: TrustStatus.paired.wire,
      ));

  Future<void> _rememberAddress(String nodeId, String name, String host, int? port) async {
    if (port == null) return;
    await db.nodesDao.upsert(NodesCompanion.insert(
      nodeId: nodeId,
      deviceName: name,
      platform: 'android',
      port: port,
      protocolVersion: kProtocolVersion,
      status: PeerStatus.online.wire,
      ipAddresses: Value(jsonEncode([host])),
      lastSeen: Value(DateTime.now().toUtc()),
    ));
    _peers[nodeId] = PeerView(
      nodeId: nodeId,
      name: name,
      status: PeerStatus.online,
      paired: true,
      host: host,
      port: port,
      lastSeen: DateTime.now(),
    );
    _emit();
    unawaited(_probe(nodeId));
  }

  /// The address other phones should use to reach this one. Prefers Wi-Fi and
  /// hotspot interfaces over cellular.
  Future<String> _localAddress() async {
    final all = await NetworkInterface.list(type: InternetAddressType.IPv4);
    int rank(String name) {
      final n = name.toLowerCase();
      if (n.startsWith('wlan') || n.startsWith('swlan')) return 0;
      if (n.startsWith('ap') || n.startsWith('en')) return 1;
      if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('pdp')) return 9;
      return 5;
    }

    final candidates = [
      for (final i in all)
        for (final a in i.addresses)
          if (!a.isLoopback) (rank(i.name), a.address),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (candidates.isEmpty) {
      throw HiveError(
        code: HiveErrorCode.backendUnavailable,
        message: 'Connect to Wi-Fi to pair devices.',
      );
    }
    return candidates.first.$2;
  }

  // ----------------------------------------------------- discovery & peers

  Future<void> startDiscovery() async {
    try {
      await _discoverySub?.cancel();
      _discoverySub = _discovery.events.listen(_onDiscovery);
      await _discovery.start(ServiceAdvertisement(
        nodeId: identity.nodeId,
        deviceName: deviceName,
        port: _server.port,
        protocolVersion: kProtocolVersion,
      ));
    } catch (_) {
      // mDNS can be blocked by the network. Paired devices still connect from
      // their saved addresses, and pairing uses the QR code.
    }
  }

  void _onDiscovery(DiscoveryEvent event) {
    if (event is PeerFound) {
      final p = event.peer;
      final existing = _peers[p.nodeId];
      _peers[p.nodeId] = PeerView(
        nodeId: p.nodeId,
        name: existing?.name ?? p.deviceName,
        status: existing?.status ?? PeerStatus.discovered,
        paired: existing?.paired ?? false,
        host: p.addresses.first,
        port: p.port,
        telemetry: existing?.telemetry,
        lastSeen: DateTime.now(),
      );
      _emit();
    } else if (event is PeerLost) {
      final v = _peers[event.nodeId];
      if (v != null && !v.paired) _peers.remove(event.nodeId);
      _emit();
    }
  }

  Future<void> _loadPairedPeers() async {
    final nodes = {for (final n in await db.nodesDao.getAll()) n.nodeId: n};
    for (final t in await db.trustedDevicesDao.getAll()) {
      if (t.trustStatus != TrustStatus.paired.wire || t.revokedAt != null) continue;
      final n = nodes[t.nodeId];
      final hosts = n == null ? const <dynamic>[] : jsonDecode(n.ipAddresses) as List;
      _peers[t.nodeId] = PeerView(
        nodeId: t.nodeId,
        name: t.displayName,
        status: PeerStatus.offline, // until a probe says otherwise
        paired: true,
        host: hosts.isEmpty ? null : hosts.first as String,
        port: n?.port,
      );
    }
    _emit();
  }

  Stream<List<PeerView>> watchPeers() async* {
    yield _snapshot();
    yield* _peerChanges.stream;
  }

  List<PeerView> _snapshot() => _peers.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  void _emit() {
    if (!_peerChanges.isClosed) _peerChanges.add(_snapshot());
  }

  Future<void> _probeAll() async {
    for (final id in _peers.values.where((p) => p.paired).map((p) => p.nodeId).toList()) {
      await _probe(id);
    }
  }

  /// Asks one paired device for its storage numbers. Success means it is online
  /// and servable now; two failures in a row mean it is not.
  Future<void> _probe(String nodeId) async {
    final view = _peers[nodeId];
    if (view == null || view.host == null) return;
    final watch = Stopwatch()..start();
    SecureChannel? channel;
    StreamIterator<MessageEnvelope>? inbox;
    try {
      channel = await dial(nodeId).timeout(const Duration(seconds: 6));
      inbox = StreamIterator(channel.messages);
      await channel.send(MessageEnvelope(
        type: MessageType.heartbeat,
        requestId: 'hb',
        senderNodeId: identity.nodeId,
        payload: const {},
      ));
      if (!await inbox.moveNext().timeout(const Duration(seconds: 5))) {
        throw StateError('closed');
      }
      final p = inbox.current.payload;
      watch.stop();
      _failures[nodeId] = 0;
      view
        ..status = PeerStatus.online
        ..lastSeen = DateTime.now()
        ..telemetry = PeerTelemetry(
          nodeId: nodeId,
          deviceName: view.name,
          protocolVersion: kProtocolVersion,
          ipAddresses: [view.host!],
          port: view.port!,
          availableStorageBytes: (p['available'] as num?)?.toInt() ?? 0,
          totalStorageBytes: (p['total'] as num?)?.toInt() ?? 0,
          reservedStorageBytes: (p['reserved'] as num?)?.toInt() ?? 0,
          activeTransfers: (p['active'] as num?)?.toInt() ?? 0,
          lastSeen: DateTime.now().toUtc(),
          status: PeerStatus.online,
          measuredLatencyMs: watch.elapsedMilliseconds,
          reliabilityScore: 90,
        );
    } catch (_) {
      final n = (_failures[nodeId] ?? 0) + 1;
      _failures[nodeId] = n;
      // One miss can be noise; two in a row means the app is not answering
      // (backgrounded, out of range, or closed).
      if (n >= 2) view.status = PeerStatus.temporarilyUnavailable;
    } finally {
      await inbox?.cancel();
      await channel?.close();
      _emit();
    }
  }

  Future<Map<String, Object?>> _telemetryReply() async {
    final used = await files.usedBytes();
    final reserved = await quota.reservedBytes;
    return {
      'available': (contributionBytes - used - reserved).clamp(0, contributionBytes),
      'total': contributionBytes,
      'reserved': reserved,
      'active': 0,
    };
  }

  // ------------------------------------------------------------- storage

  /// Disk use, for the Storage screen.
  Future<StorageStats> storageStats() async {
    Future<(int, int)> sizeOf(String dir) async {
      final d = Directory(dir);
      if (!await d.exists()) return (0, 0);
      var bytes = 0;
      var count = 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          bytes += await e.length();
          count++;
        }
      }
      return (bytes, count);
    }

    final stored = await sizeOf(paths.layout.objectsDir);
    final owned = await sizeOf(paths.layout.outgoingDir);
    final cache = await sizeOf(paths.layout.retrievedCacheDir);
    final partial = await sizeOf(paths.layout.incompleteTransfersDir);
    return StorageStats(
      replicaBytes: stored.$1,
      replicaCount: stored.$2,
      reservedBytes: await quota.reservedBytes,
      quotaBytes: contributionBytes,
      ownedBytes: owned.$1,
      cacheBytes: cache.$1,
      partialBytes: partial.$1,
    );
  }

  /// The address other phones would use to reach this one, if on a network.
  Future<String?> localAddress() async {
    try {
      return await _localAddress();
    } catch (_) {
      return null;
    }
  }

  /// Deletes decrypted images kept for viewing. Replicas and keys are untouched.
  Future<void> clearViewedCache() async {
    final d = Directory(paths.layout.retrievedCacheDir);
    if (await d.exists()) {
      await for (final e in d.list()) {
        if (e is File) await e.delete();
      }
    }
  }

  // ------------------------------------------------------------- images

  /// Compresses, encrypts and replicates an image. The original is never sent;
  /// if compression fails nothing is uploaded.
  Stream<UploadUpdate> uploadImage({
    required String sourcePath,
    required Importance importance,
    required ImageVisibility visibility,
  }) async* {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final compressed = await _compressor.compress(CompressionRequest(
      sourcePath: sourcePath,
      outputPath: '${paths.layout.outgoingDir}/compress-$stamp.jpg',
      importance: importance,
    ));
    try {
      yield* _uploads.upload(UploadRequest(
        compressedPath: compressed.path,
        fileName: sourcePath.split(Platform.pathSeparator).last,
        mimeType: compressed.mimeType,
        width: compressed.width,
        height: compressed.height,
        importance: importance,
        visibility: visibility,
      ));
    } finally {
      final f = File(compressed.path);
      if (await f.exists()) await f.delete();
    }
  }

  /// Retries replication for a gallery entry that is not fully replicated.
  Stream<UploadUpdate> retryUpload(String contentId) async* {
    final unfinished = await _replicationStore.unfinishedJobs();
    // Re-run through the same pipeline from the saved encrypted copy.
    final m = await manifests.byId(contentId);
    if (m == null) return;
    final job = unfinished.where((j) => j.contentId == contentId).firstOrNull;
    if (job == null) return;
    final plan = await DeterministicStorageRouter(trustedNodeIds: _pairedIds).plan(
      PlacementRequest(
        sizeBytes: (await File(paths.layout.outgoingPath(contentId)).length()),
        importance: m.importance,
        excludeNodeIds: {identity.nodeId},
      ),
      [for (final p in _peers.values) if (p.paired && p.telemetry != null) p.telemetry!],
    );
    final transport = ChannelReplicaTransport(
      dial: dial,
      chunks: FileChunkManager(paths.layout),
      localNodeId: identity.nodeId,
    );
    final source = ReplicationSource(
      contentId: contentId,
      objectPath: paths.layout.outgoingPath(contentId),
      ciphertextHash: m.ciphertextHash!,
      sizeBytes: await File(paths.layout.outgoingPath(contentId)).length(),
    );
    UploadJob last = job;
    await for (final s in DefaultReplicationManager(transport: transport, store: _replicationStore)
        .replicate(job, plan, source)) {
      last = s;
      yield UploadUpdate(UploadStage.replicating, contentId: contentId, job: s);
    }
    await manifests.setAvailability(contentId, UploadService.availabilityFor(last.status));
    yield UploadUpdate(UploadStage.finished, contentId: contentId, job: last);
  }

  Stream<RetrievalSession> fetchImage(String contentId) => _retrieval.fetch(contentId);

  Stream<List<ImageManifest>> watchGallery() => manifests.watchAll();

  /// Devices believed to hold a replica, online ones first.
  Future<List<String>> _holdersOf(String contentId) async {
    final rows = await db.replicasDao.forContent(contentId);
    final ids = [for (final r in rows) if (r.verified) r.nodeId];
    ids.sort((a, b) {
      int rank(String id) => _peers[id]?.status == PeerStatus.online ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    return ids;
  }

  Future<List<ReplicaRow>> replicasOf(String contentId) => db.replicasDao.forContent(contentId);

  // ------------------------------------------------------------- sharing

  /// Lets [viewerNodeId] view [contentId] (owner only).
  ///
  /// 1. Every replica holder is told the viewer may download the ciphertext.
  /// 2. The viewer receives the image key and the gallery entry directly,
  ///    over the encrypted channel. Storage devices never receive the key.
  ///
  /// The owner must be online to do this. Afterwards the viewer can fetch from
  /// any replica holder even while the owner is away.
  Future<void> shareImage(String contentId, String viewerNodeId) async {
    final manifest = await manifests.byId(contentId);
    final key = await keys.read(UploadService.keyName(contentId));
    if (manifest == null || key == null || manifest.ownerNodeId != identity.nodeId) {
      throw HiveError(
        code: HiveErrorCode.accessDenied,
        message: 'Only the owner can share this image.',
      );
    }
    await policy.grant(
      contentId: contentId,
      granteeNodeId: viewerNodeId,
      permission: PermissionType.view,
      grantedBy: identity.nodeId,
    );
    final holders = await _holdersOf(contentId);
    for (final holder in holders) {
      if (holder == viewerNodeId) continue; // it already stores it; allow it below
      await _tell(holder, MessageType.accessGrant, contentId, {'grantee': viewerNodeId});
    }
    if (holders.contains(viewerNodeId)) {
      await policy.grant(
        contentId: contentId,
        granteeNodeId: viewerNodeId,
        permission: PermissionType.retrieve,
        grantedBy: identity.nodeId,
      );
    }
    await _tell(viewerNodeId, MessageType.keyDelivery, contentId, {
      'key': base64Encode(key),
      'manifest': manifest.toJson(),
      'holders': holders,
    });
  }

  /// Stops [viewerNodeId] from fetching [contentId] again. This cannot take
  /// back a copy they already downloaded or a key they already received.
  Future<void> unshareImage(String contentId, String viewerNodeId) async {
    await policy.revoke(contentId, viewerNodeId, PermissionType.view);
    await policy.revoke(contentId, viewerNodeId, PermissionType.retrieve);
    for (final holder in await _holdersOf(contentId)) {
      try {
        await _tell(holder, MessageType.accessRevoke, contentId, {'grantee': viewerNodeId});
      } catch (_) {
        // The holder is offline; it keeps honouring the old grant until it
        // hears. The UI must say so.
      }
    }
  }

  Future<void> _tell(
    String nodeId,
    MessageType type,
    String contentId,
    Map<String, Object?> payload,
  ) async {
    SecureChannel? channel;
    StreamIterator<MessageEnvelope>? inbox;
    try {
      channel = await dial(nodeId);
      inbox = StreamIterator(channel.messages);
      await channel.send(MessageEnvelope(
        type: type,
        requestId: 'share-${DateTime.now().microsecondsSinceEpoch}',
        senderNodeId: identity.nodeId,
        contentId: contentId,
        payload: {'jobId': 'share', ...payload},
      ));
      if (!await inbox.moveNext().timeout(const Duration(seconds: 10))) {
        throw HiveError(code: HiveErrorCode.peerDisconnected, message: 'disconnected');
      }
      if (inbox.current.type == MessageType.accessDenied || inbox.current.type == MessageType.error) {
        throw HiveError(code: HiveErrorCode.accessDenied, message: 'The other device refused.');
      }
    } finally {
      await inbox?.cancel();
      await channel?.close();
    }
  }

  /// Handles sharing messages from another device (see [shareImage]).
  Future<MessageEnvelope?> _onOtherMessage(MessageEnvelope m, SecureChannel channel) async {
    MessageEnvelope reply(MessageType t, [Map<String, Object?> p = const {}]) => MessageEnvelope(
          type: t,
          requestId: m.requestId,
          senderNodeId: '',
          contentId: m.contentId,
          payload: p,
        );
    final contentId = m.contentId;
    if (contentId == null) return reply(MessageType.error, {'code': 'malformed_message'});
    final sender = channel.peerNodeId;

    switch (m.type) {
      case MessageType.accessGrant:
      case MessageType.accessRevoke:
        // Only the device that uploaded this object may change who can fetch
        // it. Everyone else is refused, however well-connected.
        if (!await policy.isOwner(sender, contentId)) return reply(MessageType.accessDenied);
        final grantee = m.payload['grantee'];
        if (grantee is! String) return reply(MessageType.error, {'code': 'malformed_message'});
        if (m.type == MessageType.accessGrant) {
          await policy.grant(
            contentId: contentId,
            granteeNodeId: grantee,
            permission: PermissionType.retrieve,
            grantedBy: sender,
          );
        } else {
          await policy.revoke(contentId, grantee, PermissionType.retrieve);
        }
        return reply(MessageType.accessGranted);

      case MessageType.keyDelivery:
        // A paired device is giving us a key and a gallery entry. The entry's
        // owner must be the device that sent it.
        final keyText = m.payload['key'];
        final manifestJson = m.payload['manifest'];
        if (keyText is! String || manifestJson is! Map) {
          return reply(MessageType.error, {'code': 'malformed_message'});
        }
        final manifest = ImageManifest.fromJson(Map<String, Object?>.from(manifestJson));
        final key = base64Decode(keyText);
        if (manifest.ownerNodeId != sender || manifest.contentId != contentId || key.length != 32) {
          return reply(MessageType.accessDenied);
        }
        await keys.write(UploadService.keyName(contentId), Uint8List.fromList(key));
        await manifests.save(manifest);
        for (final h in (m.payload['holders'] as List? ?? const []).whereType<String>()) {
          await db.replicasDao.upsert(ReplicasCompanion.insert(
            contentId: contentId,
            nodeId: h,
            status: ReplicaState.storedVerified.wire,
            verified: const Value(true),
            ciphertextHash: Value(manifest.ciphertextHash),
          ));
        }
        return reply(MessageType.accessGranted);

      default:
        return null;
    }
  }
}
