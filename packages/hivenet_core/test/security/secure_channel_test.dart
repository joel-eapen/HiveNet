import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/net.dart';

MessageEnvelope msg(String id, {Uint8List? data, Map<String, Object?> payload = const {}}) =>
    MessageEnvelope(
      type: MessageType.heartbeat,
      requestId: id,
      senderNodeId: 'whoever-claims-this',
      contentId: 'abc123',
      payload: payload,
      data: data,
    );

Uint8List patterned(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 13 + 5) % 256));

Matcher denied() =>
    isA<HiveError>().having((e) => e.code, 'code', HiveErrorCode.unauthenticated);

void main() {
  late TestDevice alice; // client
  late TestDevice bob; // server
  late SocketPair pair;

  setUp(() async {
    alice = await TestDevice.create('alice');
    bob = await TestDevice.create('bob');
    pair = await SocketPair.open();
  });
  tearDown(() => pair.close());

  group('a good connection', () {
    test('both sides learn who the other is', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      expect(ch.client.peerNodeId, bob.nodeId);
      expect(ch.server.peerNodeId, alice.nodeId);
      expect(ch.client.peerPublicKey, bob.publicKey);
      expect(ch.server.peerPublicKey, alice.publicKey);
      expect(ch.client.peerTrust, PeerTrust.trusted);
      expect(ch.server.peerTrust, PeerTrust.trusted);
      await ch.client.close();
      await ch.server.close();
    });

    test('both sides derive the same channel binding, different per connection', () async {
      final a = await handshake(pair, client: alice, server: bob);
      expect(a.client.channelBinding, a.server.channelBinding);
      final pair2 = await SocketPair.open();
      final b = await handshake(pair2, client: alice, server: bob);
      expect(b.client.channelBinding, isNot(a.client.channelBinding));
      await pair2.close();
    });

    test('messages travel in both directions with their data intact', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      final fromClient = ch.server.messages.first;
      final fromServer = ch.client.messages.first;

      final data = patterned(1024 * 1024);
      await ch.client.send(msg('c1', data: data, payload: {'k': 'v'}));
      await ch.server.send(msg('s1'));

      final got = await fromClient;
      expect(got.requestId, 'c1');
      expect(got.data, data);
      expect(got.payload, {'k': 'v'});
      expect((await fromServer).requestId, 's1');
    });

    test('many messages arrive in order', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      final received = ch.server.messages.take(200).map((m) => m.requestId).toList();
      for (var i = 0; i < 200; i++) {
        unawaited(ch.client.send(msg('m$i')));
      }
      expect(await received, [for (var i = 0; i < 200; i++) 'm$i']);
    });

    test('the sender claim inside a message is not the identity', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      final got = ch.server.messages.first;
      await ch.client.send(msg('x')); // claims to be "whoever-claims-this"
      expect((await got).senderNodeId, 'whoever-claims-this');
      expect(ch.server.peerNodeId, alice.nodeId, reason: 'the proven id is what counts');
    });

    test('closing one side ends the other side cleanly', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      final done = ch.server.messages.toList();
      await ch.client.close();
      expect(await done.timeout(const Duration(seconds: 3)), isEmpty);
    });

    test('sending after close is refused', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      await ch.client.close();
      await expectLater(ch.client.send(msg('late')), throwsA(denied()));
    });
  });

  group('who may connect', () {
    test('an unknown client is refused by the server, and the client knows', () async {
      await expectLater(
        handshake(pair, client: alice, server: bob,
            serverVerifies: verifierFor([])), // server has never paired alice
        throwsA(denied()),
      );
    });

    test('a client that was never accepted cannot believe it is connected', () async {
      // The server rejects; the client must not return a usable channel.
      Object? clientResult;
      final server = SecureChannel.accept(pair.server,
          identity: bob.identity, signer: bob.service, verifier: verifierFor([]));
      unawaited(server.then<void>((_) {}, onError: (_) {}));
      try {
        clientResult = await SecureChannel.connect(pair.client,
            identity: alice.identity,
            signer: alice.service,
            verifier: verifierFor([bob]),
            timeout: const Duration(seconds: 5));
      } catch (e) {
        clientResult = e;
      }
      expect(clientResult, isA<HiveError>());
    });

    test('a revoked device is refused even though it holds a valid key', () async {
      await expectLater(
        handshake(pair, client: alice, server: bob,
            serverVerifies: verifierFor([alice], revoked: {alice.nodeId})),
        throwsA(denied()),
      );
    });

    test('the client refuses a server it has not paired with', () async {
      await expectLater(
        handshake(pair, client: alice, server: bob, clientVerifies: verifierFor([])),
        throwsA(denied()),
      );
    });

    test('unknown peers are accepted only when pairing is allowed, and are marked unknown', () async {
      final ch = await handshake(pair, client: alice, server: bob,
          serverVerifies: verifierFor([]), serverAllowsUnknown: true);
      expect(ch.server.peerTrust, PeerTrust.unknown);
      expect(ch.client.peerTrust, PeerTrust.trusted);
    });

    test('a pinned server key (from a pairing QR) must match exactly', () async {
      final mallory = await TestDevice.create('mallory');
      await expectLater(
        handshake(pair, client: alice, server: bob,
            clientVerifies: verifierFor([], unlisted: PeerTrust.unknown),
            clientAllowsUnknown: true,
            serverAllowsUnknown: true,
            expectedServerKey: mallory.publicKey),
        throwsA(denied()),
      );
    });

    test('a pinned key that matches is accepted', () async {
      final ch = await handshake(pair, client: alice, server: bob,
          clientVerifies: verifierFor([], unlisted: PeerTrust.unknown),
          clientAllowsUnknown: true,
          serverAllowsUnknown: true,
          expectedServerKey: bob.publicKey);
      expect(ch.client.peerNodeId, bob.nodeId);
    });
  });

  group('impersonation', () {
    /// A raw client that speaks the handshake with hand-made contents.
    Future<List<Object>> rawClient(Socket socket, Map<String, Object?> hello,
        {String? sender}) async {
      final replies = <Object>[];
      final buf = LengthPrefixedBuffer(maxBodyBytes: 1 << 20);
      final done = Completer<void>();
      socket.listen((d) {
        for (final body in buf.add(d)) {
          replies.add(utf8.decode(body));
        }
      }, onDone: done.complete, onError: (_) => done.complete());
      socket.add(LengthPrefixedBuffer.frame(utf8.encode(jsonEncode(MessageEnvelope(
        type: MessageType.authHello,
        requestId: 'handshake',
        senderNodeId: sender ?? 'x',
        payload: hello,
      ).toJson()))));
      await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      return replies;
    }

    Future<Object?> serverOutcome() async {
      try {
        return await SecureChannel.accept(pair.server,
            identity: bob.identity,
            signer: bob.service,
            verifier: verifierFor([alice]),
            timeout: const Duration(seconds: 2));
      } catch (e) {
        return e;
      }
    }

    test("claiming someone else's node id with your own key is refused", () async {
      final mallory = await TestDevice.create('mallory');
      final server = serverOutcome();
      await rawClient(pair.client, {
        'pub': base64Encode(mallory.publicKey),
        'eph': base64Encode(Uint8List(32)..[0] = 9),
      }, sender: alice.nodeId); // mallory says "I am alice"
      expect(await server, denied());
    });

    test("presenting alice's real key and id without her private key is refused", () async {
      // Mallory knows alice's public key and id (both are public) but cannot
      // sign the transcript, so her AUTH_FINISH cannot verify.
      final server = serverOutcome();
      final ephemeral = Uint8List(32)..[0] = 7;
      final bytes = await rawClient(pair.client, {
        'pub': base64Encode(alice.publicKey),
        'eph': base64Encode(ephemeral),
      }, sender: alice.nodeId);
      expect(bytes, isNotEmpty, reason: 'server answered with its reply');
      pair.client.add(LengthPrefixedBuffer.frame(utf8.encode(jsonEncode(MessageEnvelope(
        type: MessageType.authFinish,
        requestId: 'handshake',
        senderNodeId: alice.nodeId,
        payload: {'sig': base64Encode(Uint8List(64))},
      ).toJson()))));
      expect(await server, denied());
    });

    test('a weak (all-zero) identity key is refused', () async {
      final server = serverOutcome();
      await rawClient(pair.client, {
        'pub': base64Encode(Uint8List(32)),
        'eph': base64Encode(Uint8List(32)..[0] = 9),
      }, sender: Ed25519DeviceIdentityService.nodeIdFor(Uint8List(32)));
      expect(await server, denied());
    });

    test('a low-order ephemeral key cannot force a predictable secret', () async {
      final server = serverOutcome();
      await rawClient(pair.client, {
        'pub': base64Encode(alice.publicKey),
        'eph': base64Encode(Uint8List(32)), // all-zero X25519 point
      }, sender: alice.nodeId);
      expect(await server, isA<HiveError>());
    });
  });

  group('malformed and silent peers', () {
    Future<Object?> serverOutcome({Duration timeout = const Duration(seconds: 2)}) async {
      try {
        return await SecureChannel.accept(pair.server,
            identity: bob.identity,
            signer: bob.service,
            verifier: verifierFor([alice]),
            timeout: timeout);
      } catch (e) {
        return e;
      }
    }

    test('garbage instead of a handshake fails cleanly', () async {
      final server = serverOutcome();
      pair.client.add(LengthPrefixedBuffer.frame(utf8.encode('not json at all')));
      expect(await server, denied());
    });

    test('valid JSON of the wrong shape fails cleanly', () async {
      final server = serverOutcome();
      pair.client.add(LengthPrefixedBuffer.frame(utf8.encode('[1,2,3]')));
      expect(await server, denied());
    });

    test('the wrong first message type fails cleanly', () async {
      final server = serverOutcome();
      pair.client.add(LengthPrefixedBuffer.frame(utf8.encode(jsonEncode(
          msg('x').toJson()))));
      expect(await server, denied());
    });

    test('missing fields fail cleanly', () async {
      final server = serverOutcome();
      pair.client.add(LengthPrefixedBuffer.frame(utf8.encode(jsonEncode(MessageEnvelope(
        type: MessageType.authHello,
        requestId: 'h',
        senderNodeId: alice.nodeId,
      ).toJson()))));
      expect(await server, denied());
    });

    test('an oversized length prefix is refused without waiting for the body', () async {
      final server = serverOutcome();
      pair.client.add((ByteData(4)..setUint32(0, 0x7fffffff)).buffer.asUint8List());
      expect(await server, isA<HiveError>());
    });

    test('a peer that says nothing times out instead of hanging', () async {
      final sw = Stopwatch()..start();
      final out = await serverOutcome(timeout: const Duration(milliseconds: 300));
      sw.stop();
      expect(out, denied());
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });

    test('a peer that disconnects mid-handshake fails cleanly', () async {
      final server = serverOutcome();
      pair.client.destroy();
      expect(await server, isA<HiveError>());
    });
  });

  group('an attacker on the network', () {
    late Socket client;
    late Socket server;
    late Mitm mitm;
    late ServerSocket listener;

    setUp(() async {
      final c = await connectThroughMitm();
      client = c.client;
      server = c.server;
      mitm = c.mitm;
      listener = c.listener;
    });
    tearDown(() async {
      client.destroy();
      server.destroy();
      await mitm.close();
      await listener.close();
    });

    Future<({SecureChannel client, SecureChannel server})> connectBoth() async {
      final s = SecureChannel.accept(server,
          identity: bob.identity, signer: bob.service, verifier: verifierFor([alice]));
      final c = SecureChannel.connect(client,
          identity: alice.identity, signer: alice.service, verifier: verifierFor([bob]));
      return (client: await c, server: await s);
    }

    test('cannot read the traffic', () async {
      final ch = await connectBoth();
      const secret = 'TOP-SECRET-MARKER-9f3a';
      final got = ch.server.messages.first;
      await ch.client.send(msg('x', payload: {'note': secret}, data: Uint8List.fromList(utf8.encode(secret))));
      await got;
      final seen = latin1.decode(mitm.clientToServer.toBytes());
      expect(seen, isNot(contains(secret)));
      expect(seen, isNot(contains('heartbeat')));
      expect(seen, isNot(contains('abc123')), reason: 'content id is not visible either');
    });

    test('a flipped bit in a message closes the channel with an integrity error', () async {
      final ch = await connectBoth();
      var armed = false;
      mitm.tamperClientToServer = (d) {
        if (!armed) return d;
        final copy = Uint8List.fromList(d);
        copy[copy.length ~/ 2] ^= 0x01;
        return copy;
      };
      armed = true;
      final result = ch.server.messages.first;
      await ch.client.send(msg('tampered', data: patterned(2000)));
      await expectLater(result, throwsA(isA<HiveError>()
          .having((e) => e.code, 'code', HiveErrorCode.integrityMismatch)));
    });

    test('a replayed message is rejected', () async {
      final ch = await connectBoth();
      final seen = <String>[];
      final errors = <Object>[];
      ch.server.messages.listen((m) => seen.add(m.requestId), onError: errors.add);
      mitm.duplicateClientToServer = true;
      await ch.client.send(msg('once'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(seen, ['once'], reason: 'delivered exactly once');
      expect(errors, hasLength(1), reason: 'the copy was detected');
    });

    test('a dropped message is detected by the next one', () async {
      final ch = await connectBoth();
      var dropNext = true;
      mitm.tamperClientToServer = (d) {
        if (dropNext) {
          dropNext = false;
          return const <int>[]; // swallow the first message
        }
        return d;
      };
      final errors = <Object>[];
      final seen = <String>[];
      ch.server.messages.listen((m) => seen.add(m.requestId), onError: errors.add);
      await ch.client.send(msg('lost'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await ch.client.send(msg('after'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(seen, isEmpty, reason: 'nothing after a gap is accepted');
      expect(errors, isNotEmpty);
    });

    test('tampering with the handshake is detected', () async {
      var flipped = false;
      mitm.tamperServerToClient = (d) {
        if (flipped) return d;
        flipped = true;
        final copy = Uint8List.fromList(d);
        copy[copy.length - 20] ^= 0x01; // inside the server reply
        return copy;
      };
      await expectLater(connectBoth(), throwsA(isA<HiveError>()));
    });
  });

  group('sessions are independent', () {
    test('a message recorded in one session means nothing in another', () async {
      final c1 = await connectThroughMitm();
      final s1 = SecureChannel.accept(c1.server,
          identity: bob.identity, signer: bob.service, verifier: verifierFor([alice]));
      final a1 = SecureChannel.connect(c1.client,
          identity: alice.identity, signer: alice.service, verifier: verifierFor([bob]));
      final first = (client: await a1, server: await s1);
      await first.client.send(msg('recorded'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final recorded = Uint8List.fromList(c1.mitm.clientToServer.toBytes());

      // New session between the same two devices; replay the old bytes at it.
      final c2 = await connectThroughMitm();
      final s2 = SecureChannel.accept(c2.server,
          identity: bob.identity, signer: bob.service, verifier: verifierFor([alice]));
      final a2 = SecureChannel.connect(c2.client,
          identity: alice.identity, signer: alice.service, verifier: verifierFor([bob]));
      final second = (client: await a2, server: await s2);
      final seen = <String>[];
      final errors = <Object>[];
      second.server.messages.listen((m) => seen.add(m.requestId), onError: errors.add);

      // The tail of the recording is the encrypted message from session one.
      c2.client.add(recorded.sublist(recorded.length - 120));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(seen, isEmpty);
      expect(errors, isNotEmpty);

      for (final c in [c1, c2]) {
        c.client.destroy();
        c.server.destroy();
        await c.mitm.close();
        await c.listener.close();
      }
    });
  });

  group('limits', () {
    test('a message above the limit is refused locally', () async {
      final ch = await handshake(pair, client: alice, server: bob);
      await expectLater(
        ch.client.send(msg('big', data: Uint8List(5 * 1024 * 1024))),
        throwsA(isA<HiveError>()
            .having((e) => e.code, 'code', HiveErrorCode.oversizedMessage)),
      );
      // The channel is still usable afterwards.
      final got = ch.server.messages.first;
      await ch.client.send(msg('small'));
      expect((await got).requestId, 'small');
    });
  });
}
