import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/net.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 12);
  late TestDevice inviter; // shows the QR code
  late TestDevice joiner; // scans it
  late SocketPair pair;
  late Uint8List secret;
  late PairingInvite invite;
  late PairingInviteState state;
  final inviterSaved = <TrustedDevice>[];
  final joinerSaved = <TrustedDevice>[];

  PairingInvite makeInvite({DateTime? expires, Uint8List? key, String? id, String host = '10.0.0.5', int port = 4000}) =>
      PairingInvite(
        nodeId: id ?? inviter.nodeId,
        publicKey: key ?? inviter.publicKey,
        host: host,
        port: port,
        secret: secret,
        expiresAt: expires ?? t0.add(const Duration(minutes: 5)),
      );

  setUp(() async {
    inviter = await TestDevice.create('Joel phone');
    joiner = await TestDevice.create('Tushar phone');
    pair = await SocketPair.open();
    secret = Uint8List.fromList(List.generate(16, (i) => i * 7 + 1));
    invite = makeInvite();
    state = PairingInviteState(invite: invite, clock: () => t0);
    inviterSaved.clear();
    joinerSaved.clear();
  });
  tearDown(() => pair.close());

  /// Opens the two secure channels the way the app will for pairing.
  Future<({SecureChannel joiner, SecureChannel inviter})> channels({
    Uint8List? pinnedKey,
  }) async {
    final server = SecureChannel.accept(pair.server,
        identity: inviter.identity,
        signer: inviter.service,
        verifier: verifierFor([]),
        allowUnknown: true);
    final client = SecureChannel.connect(pair.client,
        identity: joiner.identity,
        signer: joiner.service,
        verifier: verifierFor([], unlisted: PeerTrust.unknown),
        allowUnknown: true,
        expectedPeerKey: pinnedKey ?? invite.publicKey);
    final r = await Future.wait([
      client.then<Object>((v) => v, onError: (Object e) => e),
      server.then<Object>((v) => v, onError: (Object e) => e),
    ]);
    for (final x in r) {
      if (x is! SecureChannel) throw x;
    }
    return (joiner: r[0] as SecureChannel, inviter: r[1] as SecureChannel);
  }

  Future<List<Object>> runBoth(
    ({SecureChannel joiner, SecureChannel inviter}) ch, {
    bool joinerAccepts = true,
    bool inviterAccepts = true,
    PairingInviteState? inviteState,
  }) {
    final j = runPairingAsJoiner(
      channel: ch.joiner,
      invite: invite,
      self: joiner.identity,
      confirm: (_, _) => joinerAccepts,
      save: (d) async => joinerSaved.add(d),
      timeout: const Duration(seconds: 3),
      clock: () => t0,
    );
    final i = runPairingAsInviter(
      channel: ch.inviter,
      state: inviteState ?? state,
      self: inviter.identity,
      confirm: (_, _) => inviterAccepts,
      save: (d) async => inviterSaved.add(d),
      timeout: const Duration(seconds: 3),
      clock: () => t0,
    );
    return Future.wait([
      j.then<Object>((v) => v, onError: (Object e) => e),
      i.then<Object>((v) => v, onError: (Object e) => e),
    ]);
  }

  group('the QR code', () {
    test('survives a round trip', () {
      final back = PairingInvite.parse(invite.toQrString(), now: t0);
      expect(back.nodeId, invite.nodeId);
      expect(back.publicKey, invite.publicKey);
      expect(back.host, '10.0.0.5');
      expect(back.port, 4000);
      expect(back.secret, invite.secret);
    });

    test('is not valid after it expires', () {
      final text = makeInvite(expires: t0.add(const Duration(minutes: 1))).toQrString();
      expect(() => PairingInvite.parse(text, now: t0.add(const Duration(minutes: 2))),
          throwsA(isA<HiveError>()));
      expect(PairingInvite.parse(text, now: t0).nodeId, inviter.nodeId);
    });

    // Built inside the test so the devices from setUp exist.
    void rejects(String why, PairingInvite Function() bad) {
      test('is rejected: $why', () {
        expect(() => PairingInvite.parse(bad().toQrString(), now: t0), throwsA(isA<HiveError>()));
      });
    }

    rejects('id does not match the key', () => makeInvite(id: joiner.nodeId));
    rejects('weak key', () => makeInvite(key: Uint8List(32), id: Ed25519DeviceIdentityService.nodeIdFor(Uint8List(32))));
    rejects('port out of range', () => makeInvite(port: 70000));
    rejects('empty host', () => makeInvite(host: ''));

    test('is rejected: not a HiveNet code, garbage, wrong secret length', () {
      for (final text in [
        'https://example.com',
        '',
        '${PairingInvite.scheme}!!!notbase64',
        '${PairingInvite.scheme}${base64Url.encode(utf8.encode('{"v":1}'))}',
        '${PairingInvite.scheme}${base64Url.encode(utf8.encode('[]'))}',
      ]) {
        expect(() => PairingInvite.parse(text, now: t0), throwsA(isA<HiveError>()), reason: text);
      }
      final shortSecret = PairingInvite(
          nodeId: inviter.nodeId, publicKey: inviter.publicKey, host: 'h', port: 1,
          secret: Uint8List(4), expiresAt: t0.add(const Duration(minutes: 1)));
      expect(() => PairingInvite.parse(shortSecret.toQrString(), now: t0), throwsA(isA<HiveError>()));
    });

    test('errors do not echo the secret', () {
      try {
        PairingInvite.parse(makeInvite(id: joiner.nodeId).toQrString(), now: t0);
        fail('should throw');
      } on HiveError catch (e) {
        expect('${e.message} ${e.technicalDetails}', isNot(contains(base64Encode(secret))));
      }
    });
  });

  group('a successful pairing', () {
    test('both sides end up trusting each other', () async {
      final r = await runBoth(await channels());
      expect(r.every((x) => x is TrustedDevice), isTrue, reason: '$r');

      expect(joinerSaved, hasLength(1));
      expect(inviterSaved, hasLength(1));
      expect(joinerSaved.single.nodeId, inviter.nodeId);
      expect(inviterSaved.single.nodeId, joiner.nodeId);
      expect(joinerSaved.single.trustStatus, TrustStatus.paired);
      expect(inviterSaved.single.displayName, 'Tushar phone');
      expect(joinerSaved.single.displayName, 'Joel phone');
      expect(inviterSaved.single.publicKey, base64Encode(joiner.publicKey));
    });

    test('each user is shown the other device\'s fingerprint', () async {
      String? joinerSaw, inviterSaw;
      final ch = await channels();
      final results = await Future.wait([
        runPairingAsJoiner(
          channel: ch.joiner, invite: invite, self: joiner.identity,
          confirm: (name, fp) { joinerSaw = fp; return true; },
          save: (d) async {}, timeout: const Duration(seconds: 3), clock: () => t0)
            .then<Object>((v) => v, onError: (Object e) => e),
        runPairingAsInviter(
          channel: ch.inviter, state: state, self: inviter.identity,
          confirm: (name, fp) { inviterSaw = fp; return true; },
          save: (d) async {}, timeout: const Duration(seconds: 3), clock: () => t0)
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.every((x) => x is TrustedDevice), isTrue);
      expect(joinerSaw, Ed25519DeviceIdentityService.fingerprintFor(inviter.publicKey));
      expect(inviterSaw, Ed25519DeviceIdentityService.fingerprintFor(joiner.publicKey));
    });

    test('afterwards they can connect as ordinary trusted peers', () async {
      await runBoth(await channels());
      final inviterVerifier = trustedDeviceVerifier(
          (id) => inviterSaved.where((d) => d.nodeId == id).firstOrNull);
      final joinerVerifier = trustedDeviceVerifier(
          (id) => joinerSaved.where((d) => d.nodeId == id).firstOrNull);

      final pair2 = await SocketPair.open();
      final ch = await handshake(pair2,
          client: joiner, server: inviter,
          clientVerifies: joinerVerifier, serverVerifies: inviterVerifier);
      expect(ch.client.peerTrust, PeerTrust.trusted);
      expect(ch.server.peerTrust, PeerTrust.trusted);
      await pair2.close();
    });
  });

  group('refusals', () {
    test('if the inviter declines, nothing is saved anywhere', () async {
      final r = await runBoth(await channels(), inviterAccepts: false);
      expect(r.every((x) => x is HiveError), isTrue, reason: '$r');
      expect(joinerSaved, isEmpty);
      expect(inviterSaved, isEmpty);
    });

    test('if the joiner declines, nothing is saved anywhere', () async {
      final r = await runBoth(await channels(), joinerAccepts: false);
      expect(r.every((x) => x is HiveError), isTrue, reason: '$r');
      expect(joinerSaved, isEmpty);
      expect(inviterSaved, isEmpty);
    });

    test('a joiner that never answers does not hang the inviter', () async {
      final ch = await channels();
      final sw = Stopwatch()..start();
      final out = await runPairingAsInviter(
        channel: ch.inviter, state: state, self: inviter.identity,
        confirm: (_, _) => true, save: (d) async => inviterSaved.add(d),
        timeout: const Duration(milliseconds: 300), clock: () => t0,
      ).then<Object>((v) => v, onError: (Object e) => e);
      expect(out, isA<HiveError>());
      expect(sw.elapsedMilliseconds, lessThan(2500));
      expect(inviterSaved, isEmpty);
    });
  });

  group('attacks', () {
    test('someone who did not scan the code cannot pair (wrong secret)', () async {
      final ch = await channels();
      // The attacker connects fine (anyone on the LAN can) but guesses the proof.
      await ch.joiner.send(MessageEnvelope(
        type: MessageType.pairRequest, requestId: 'pair', senderNodeId: joiner.nodeId,
        payload: {
          'name': 'attacker',
          'proof': base64Encode(pairingProof(
              secret: Uint8List(16), // wrong secret
              channelBinding: ch.joiner.channelBinding,
              joinerNodeId: joiner.nodeId)),
        },
      ));
      final out = await runPairingAsInviter(
        channel: ch.inviter, state: state, self: inviter.identity,
        confirm: (_, _) => true, save: (d) async => inviterSaved.add(d),
        timeout: const Duration(seconds: 2), clock: () => t0,
      ).then<Object>((v) => v, onError: (Object e) => e);
      expect(out, isA<HiveError>()
          .having((e) => e.technicalDetails, 'reason', contains('invalid, used or expired')));
      expect(inviterSaved, isEmpty, reason: 'nothing may be saved');
    });

    test('a request with no proof at all is refused', () async {
      final ch = await channels();
      await ch.joiner.send(MessageEnvelope(
          type: MessageType.pairRequest, requestId: 'pair',
          senderNodeId: joiner.nodeId, payload: {'name': 'x'}));
      final out = await runPairingAsInviter(
        channel: ch.inviter, state: state, self: inviter.identity,
        confirm: (_, _) => true, save: (d) async => inviterSaved.add(d),
        timeout: const Duration(seconds: 2), clock: () => t0,
      ).then<Object>((v) => v, onError: (Object e) => e);
      expect(out, isA<HiveError>()
          .having((e) => e.technicalDetails, 'reason', contains('invalid, used or expired')));
      expect(inviterSaved, isEmpty);
    });

    test('a correct proof made for a different connection is useless', () async {
      // Attacker records the real joiner's proof on connection A and replays it
      // on connection B. The channel binding differs, so it must fail.
      final ch = await channels();
      final proofForOtherConnection = pairingProof(
          secret: secret, channelBinding: Uint8List(32), joinerNodeId: joiner.nodeId);
      await ch.joiner.send(MessageEnvelope(
          type: MessageType.pairRequest, requestId: 'pair', senderNodeId: joiner.nodeId,
          payload: {'name': 'x', 'proof': base64Encode(proofForOtherConnection)}));
      final out = await runPairingAsInviter(
        channel: ch.inviter, state: state, self: inviter.identity,
        confirm: (_, _) => true, save: (d) async => inviterSaved.add(d),
        timeout: const Duration(seconds: 2), clock: () => t0,
      ).then<Object>((v) => v, onError: (Object e) => e);
      expect(out, isA<HiveError>()
          .having((e) => e.technicalDetails, 'reason', contains('invalid, used or expired')));
      expect(inviterSaved, isEmpty);
    });

    test('a proof made for another joiner id is useless', () async {
      final ch = await channels();
      final other = await TestDevice.create('other');
      final stolen = pairingProof(
          secret: secret, channelBinding: ch.joiner.channelBinding, joinerNodeId: other.nodeId);
      await ch.joiner.send(MessageEnvelope(
          type: MessageType.pairRequest, requestId: 'pair', senderNodeId: joiner.nodeId,
          payload: {'name': 'x', 'proof': base64Encode(stolen)}));
      final out = await runPairingAsInviter(
        channel: ch.inviter, state: state, self: inviter.identity,
        confirm: (_, _) => true, save: (d) async => inviterSaved.add(d),
        timeout: const Duration(seconds: 2), clock: () => t0,
      ).then<Object>((v) => v, onError: (Object e) => e);
      expect(out, isA<HiveError>()
          .having((e) => e.technicalDetails, 'reason', contains('invalid, used or expired')));
      expect(inviterSaved, isEmpty);
    });

    test('the code works only once', () async {
      expect((await runBoth(await channels())).every((x) => x is TrustedDevice), isTrue);

      // A second device tries the same (already used) code.
      final second = await TestDevice.create('latecomer');
      final pair2 = await SocketPair.open();
      final server = SecureChannel.accept(pair2.server,
          identity: inviter.identity, signer: inviter.service,
          verifier: verifierFor([]), allowUnknown: true);
      final client = await SecureChannel.connect(pair2.client,
          identity: second.identity, signer: second.service,
          verifier: verifierFor([], unlisted: PeerTrust.unknown), allowUnknown: true,
          expectedPeerKey: invite.publicKey);
      final serverCh = await server;
      final extraSaved = <TrustedDevice>[];
      final results = await Future.wait([
        runPairingAsJoiner(
          channel: client, invite: invite, self: second.identity,
          confirm: (_, _) => true, save: (d) async {},
          timeout: const Duration(seconds: 2), clock: () => t0,
        ).then<Object>((v) => v, onError: (Object e) => e),
        runPairingAsInviter(
          channel: serverCh, state: state, self: inviter.identity,
          confirm: (_, _) => true, save: (d) async => extraSaved.add(d),
          timeout: const Duration(seconds: 2), clock: () => t0,
        ).then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.every((x) => x is HiveError), isTrue, reason: '$results');
      expect(extraSaved, isEmpty);
      await pair2.close();
    });

    test('an expired invite state refuses even a correct proof', () async {
      final ch = await channels();
      final expired = PairingInviteState(
          invite: makeInvite(expires: t0.subtract(const Duration(seconds: 1))), clock: () => t0);
      final results = await runBoth(ch, inviteState: expired);
      expect(results.every((x) => x is HiveError), isTrue, reason: '$results');
      expect(inviterSaved, isEmpty);
    });

    test('too many wrong guesses lock the invite, even for the right proof', () {
      for (var i = 0; i < 3; i++) {
        expect(state.verifyAndConsume(
            proof: Uint8List(32), channelBinding: Uint8List(32), joinerNodeId: 'x'), isFalse);
      }
      final right = pairingProof(secret: secret, channelBinding: Uint8List(32), joinerNodeId: 'x');
      expect(state.isUsable, isFalse);
      expect(state.verifyAndConsume(proof: right, channelBinding: Uint8List(32), joinerNodeId: 'x'), isFalse);
    });

    test('a man in the middle with his own key cannot be paired with (key pinned by the QR)', () async {
      final mallory = await TestDevice.create('mallory');
      // The joiner dials what it thinks is the inviter but reaches mallory.
      final server = SecureChannel.accept(pair.server,
          identity: mallory.identity, signer: mallory.service,
          verifier: verifierFor([]), allowUnknown: true);
      server.then<void>((_) {}, onError: (_) {});
      await expectLater(
        SecureChannel.connect(pair.client,
            identity: joiner.identity, signer: joiner.service,
            verifier: verifierFor([], unlisted: PeerTrust.unknown),
            allowUnknown: true,
            expectedPeerKey: invite.publicKey,
            timeout: const Duration(seconds: 3)),
        throwsA(isA<HiveError>()),
      );
    });
  });

  group('trusted device verifier', () {
    TrustedDevice device({TrustStatus status = TrustStatus.paired, DateTime? revoked, Uint8List? key}) =>
        TrustedDevice(
          nodeId: joiner.nodeId, publicKey: base64Encode(key ?? joiner.publicKey),
          fingerprint: 'fp', displayName: 'x', pairedAt: t0, trustStatus: status, revokedAt: revoked);

    test('paired with the matching key is trusted', () async {
      final v = trustedDeviceVerifier((_) => device());
      expect(await v(joiner.nodeId, joiner.publicKey), PeerTrust.trusted);
    });

    test('never seen is unknown', () async {
      final v = trustedDeviceVerifier((_) => null);
      expect(await v(joiner.nodeId, joiner.publicKey), PeerTrust.unknown);
    });

    test('revoked is rejected, by status or by timestamp', () async {
      expect(await trustedDeviceVerifier((_) => device(status: TrustStatus.revoked))(joiner.nodeId, joiner.publicKey),
          PeerTrust.rejected);
      expect(await trustedDeviceVerifier((_) => device(revoked: t0))(joiner.nodeId, joiner.publicKey),
          PeerTrust.rejected);
    });

    test('a different key than the one paired is rejected', () async {
      final other = await TestDevice.create('o');
      final v = trustedDeviceVerifier((_) => device());
      expect(await v(joiner.nodeId, other.publicKey), PeerTrust.rejected);
    });

    test('an unpaired (not-yet-confirmed) entry is rejected, not trusted', () async {
      final v = trustedDeviceVerifier((_) => device(status: TrustStatus.unpaired));
      expect(await v(joiner.nodeId, joiner.publicKey), PeerTrust.rejected);
    });
  });
}
