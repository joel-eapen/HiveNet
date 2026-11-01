import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hivenet/spike/spike_wire.dart';

void main() {
  Uint8List chunkBytes(int n) =>
      Uint8List.fromList(List.generate(n, (i) => i % 251));

  test('round trips a binary frame', () {
    final payload = chunkBytes(1000);
    final frames = FrameReader().add(encodeFrame(SpikeMsg.chunk, payload));
    expect(frames, hasLength(1));
    expect(frames.single.type, SpikeMsg.chunk);
    expect(frames.single.payload, payload);
  });

  test('reassembles a frame delivered one byte at a time', () {
    final reader = FrameReader();
    final bytes = encodeFrame(SpikeMsg.begin, jsonPayload({'a': 1}));
    final out = <Frame>[];
    for (final b in bytes) {
      out.addAll(reader.add([b]));
    }
    expect(out, hasLength(1));
    expect(out.single.json, {'a': 1});
  });

  test('splits several frames coalesced into one read', () {
    final joined = BytesBuilder()
      ..add(encodeFrame(SpikeMsg.heartbeat))
      ..add(encodeFrame(SpikeMsg.ack, jsonPayload({'received': 5})))
      ..add(encodeFrame(SpikeMsg.chunk, chunkBytes(10)));
    final frames = FrameReader().add(joined.toBytes());
    expect(frames.map((f) => f.type),
        [SpikeMsg.heartbeat, SpikeMsg.ack, SpikeMsg.chunk]);
  });

  test('handles a 1 MiB chunk split across uneven reads', () {
    final payload = chunkBytes(1024 * 1024);
    final bytes = encodeFrame(SpikeMsg.chunk, payload);
    final reader = FrameReader();
    final out = <Frame>[];
    for (var i = 0; i < bytes.length; i += 40000) {
      out.addAll(reader.add(bytes.sublist(i, (i + 40000).clamp(0, bytes.length))));
    }
    expect(out, hasLength(1));
    expect(out.single.payload, payload);
  });

  test('keeps the start of the next frame when a read ends mid-frame', () {
    final a = encodeFrame(SpikeMsg.chunk, chunkBytes(100));
    final b = encodeFrame(SpikeMsg.ack, jsonPayload({'received': 1}));
    final all = Uint8List.fromList([...a, ...b]);
    final reader = FrameReader();
    final first = reader.add(all.sublist(0, a.length + 3));
    final second = reader.add(all.sublist(a.length + 3));
    expect(first.map((f) => f.type), [SpikeMsg.chunk]);
    expect(second.map((f) => f.type), [SpikeMsg.ack]);
  });

  test('rejects an oversized length before buffering the body', () {
    final prefix = ByteData(4)..setUint32(0, spikeMaxFrame + 1);
    expect(() => FrameReader().add(prefix.buffer.asUint8List()),
        throwsFormatException);
  });

  test('rejects a zero length and an unknown message type', () {
    expect(() => FrameReader().add([0, 0, 0, 0]), throwsFormatException);
    expect(() => FrameReader().add([0, 0, 0, 1, 99]), throwsFormatException);
  });

  test('refuses to encode a frame above the limit', () {
    expect(() => encodeFrame(SpikeMsg.chunk, Uint8List(spikeMaxFrame)),
        throwsArgumentError);
  });
}
