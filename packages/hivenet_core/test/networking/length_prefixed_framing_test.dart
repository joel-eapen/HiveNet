import 'dart:async';
import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

MessageEnvelope msg({
  MessageType type = MessageType.chunkData,
  String requestId = 'r1',
  Uint8List? data,
  Map<String, Object?> payload = const {'index': 3},
}) =>
    MessageEnvelope(
      type: type,
      requestId: requestId,
      senderNodeId: 'node-a',
      contentId: 'abc123',
      payload: payload,
      data: data,
    );

Uint8List bytesOf(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7) % 251));

void expectSame(MessageEnvelope a, MessageEnvelope b) {
  expect(b.toJson(), a.toJson());
  expect(b.data, a.data);
}

void main() {
  final framing = LengthPrefixedFraming();
  FrameDecoder newDecoder([int max = 4 * 1024 * 1024]) =>
      FrameDecoder(maxFrameBytes: max);

  HiveErrorCode codeOf(void Function() body) {
    try {
      body();
    } on HiveError catch (e) {
      return e.code;
    }
    fail('expected a HiveError');
  }

  group('encoding', () {
    test('uses the documented layout', () {
      final out = framing.encode(msg(data: Uint8List.fromList([9, 8, 7])));
      final view = ByteData.sublistView(out);
      final frameLength = view.getUint32(0);
      final headerLength = view.getUint32(4);
      expect(out.length, 4 + frameLength);
      expect(frameLength, 4 + headerLength + 3);
      expect(out.sublist(out.length - 3), [9, 8, 7]);
    });

    test('rejects a message above the limit', () {
      final small = LengthPrefixedFraming(maxFrameBytes: 100);
      expect(codeOf(() => small.encode(msg(data: bytesOf(500)))),
          HiveErrorCode.oversizedMessage);
    });
  });

  group('decoding', () {
    test('round trips a message with and without binary data', () {
      for (final m in [msg(), msg(data: bytesOf(5000))]) {
        final out = newDecoder().add(framing.encode(m));
        expect(out, hasLength(1));
        expectSame(m, out.single);
      }
    });

    test('round trips a 1 MiB chunk', () {
      final m = msg(data: bytesOf(1024 * 1024));
      final out = newDecoder().add(framing.encode(m));
      expectSame(m, out.single);
    });

    test('reassembles a frame delivered one byte at a time', () {
      final m = msg(data: bytesOf(300));
      final decoder = newDecoder();
      final out = <MessageEnvelope>[];
      for (final b in framing.encode(m)) {
        out.addAll(decoder.add([b]));
      }
      expect(out, hasLength(1));
      expectSame(m, out.single);
      expect(decoder.hasPartialFrame, isFalse);
    });

    test('splits several frames that arrive in one read', () {
      final messages = [
        msg(requestId: 'a'),
        msg(requestId: 'b', data: bytesOf(10)),
        msg(requestId: 'c', type: MessageType.heartbeat, payload: const {}),
      ];
      final joined = BytesBuilder();
      for (final m in messages) {
        joined.add(framing.encode(m));
      }
      final out = newDecoder().add(joined.toBytes());
      expect(out.map((m) => m.requestId), ['a', 'b', 'c']);
    });

    test('keeps the start of the next frame when a read ends mid-frame', () {
      final first = framing.encode(msg(requestId: 'a', data: bytesOf(100)));
      final second = framing.encode(msg(requestId: 'b'));
      final all = Uint8List.fromList([...first, ...second]);
      final decoder = newDecoder();
      final one = decoder.add(all.sublist(0, first.length + 5));
      final two = decoder.add(all.sublist(first.length + 5));
      expect(one.map((m) => m.requestId), ['a']);
      expect(two.map((m) => m.requestId), ['b']);
    });

    test('works across uneven reads of a large frame', () {
      final m = msg(data: bytesOf(1024 * 1024));
      final bytes = framing.encode(m);
      final decoder = newDecoder();
      final out = <MessageEnvelope>[];
      for (var i = 0; i < bytes.length; i += 33333) {
        out.addAll(decoder.add(
            bytes.sublist(i, i + 33333 > bytes.length ? bytes.length : i + 33333)));
      }
      expect(out, hasLength(1));
      expectSame(m, out.single);
    });
  });

  group('hostile or broken input', () {
    test('rejects an oversized length as soon as the prefix arrives', () {
      final decoder = newDecoder(1000);
      final prefix = ByteData(4)..setUint32(0, 1001);
      // Only four bytes sent: it must not wait for the body.
      expect(codeOf(() => decoder.add(prefix.buffer.asUint8List())),
          HiveErrorCode.oversizedMessage);
    });

    test('rejects a length too small to hold a header', () {
      final prefix = ByteData(4)..setUint32(0, 2);
      expect(codeOf(() => newDecoder().add(prefix.buffer.asUint8List())),
          HiveErrorCode.malformedMessage);
    });

    test('rejects a header length larger than the frame', () {
      final b = ByteData(8)
        ..setUint32(0, 4)
        ..setUint32(4, 99);
      expect(codeOf(() => newDecoder().add(b.buffer.asUint8List())),
          HiveErrorCode.malformedMessage);
    });

    Uint8List rawFrame(List<int> header) {
      final out = Uint8List(8 + header.length);
      final v = ByteData.sublistView(out);
      v.setUint32(0, 4 + header.length);
      v.setUint32(4, header.length);
      out.setRange(8, out.length, header);
      return out;
    }

    test('rejects invalid JSON, non-objects and missing fields', () {
      expect(codeOf(() => newDecoder().add(rawFrame('{oops'.codeUnits))),
          HiveErrorCode.malformedMessage);
      expect(codeOf(() => newDecoder().add(rawFrame('[1,2]'.codeUnits))),
          HiveErrorCode.malformedMessage);
      expect(codeOf(() => newDecoder().add(rawFrame('{"v":1}'.codeUnits))),
          HiveErrorCode.malformedMessage);
    });

    test('rejects an unknown message type', () {
      const json =
          '{"v":1,"type":"NOPE","requestId":"r","sender":"n","payload":{}}';
      expect(codeOf(() => newDecoder().add(rawFrame(json.codeUnits))),
          HiveErrorCode.malformedMessage);
    });

    test('stays failed after an error', () {
      final decoder = newDecoder();
      expect(codeOf(() => decoder.add(rawFrame('{oops'.codeUnits))),
          HiveErrorCode.malformedMessage);
      expect(codeOf(() => decoder.add(framing.encode(msg()))),
          HiveErrorCode.malformedMessage);
    });
  });

  group('stream decode', () {
    test('emits messages in order', () async {
      final bytes = BytesBuilder()
        ..add(framing.encode(msg(requestId: 'a')))
        ..add(framing.encode(msg(requestId: 'b')));
      final all = bytes.toBytes();
      final stream = Stream.fromIterable([
        all.sublist(0, 7),
        all.sublist(7, all.length - 1),
        all.sublist(all.length - 1),
      ]);
      final out = await framing.decode(stream).toList();
      expect(out.map((m) => m.requestId), ['a', 'b']);
    });

    test('errors if the connection closes in the middle of a frame', () async {
      final bytes = framing.encode(msg(data: bytesOf(50)));
      final stream = Stream.value(bytes.sublist(0, bytes.length - 10));
      await expectLater(
        framing.decode(stream).toList(),
        throwsA(isA<HiveError>()
            .having((e) => e.code, 'code', HiveErrorCode.malformedMessage)),
      );
    });

    test('an empty stream is fine', () async {
      expect(await framing.decode(const Stream.empty()).toList(), isEmpty);
    });
  });
}
