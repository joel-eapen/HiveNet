// THROWAWAY Milestone 0 spike code (PRD section 10.6).
//
// Purpose: prove that framed TCP, chunk ACKs and resume work on real phones.
// The production protocol lives in packages/hivenet_core and will replace this.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Spike message types. Wire code is one byte.
enum SpikeMsg {
  hello(1),
  begin(2),
  resumeAt(3),
  chunk(4),
  ack(5),
  done(6),
  heartbeat(7);

  const SpikeMsg(this.code);
  final int code;

  static SpikeMsg fromCode(int code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    throw FormatException('Unknown message code $code');
  }
}

class Frame {
  Frame(this.type, this.payload);
  final SpikeMsg type;
  final Uint8List payload;

  Map<String, Object?> get json =>
      jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
}

/// Frames above this size are rejected before their body is buffered.
const int spikeMaxFrame = 4 * 1024 * 1024;

/// `[u32 length][u8 type][payload]`, big-endian, length covers type + payload.
Uint8List encodeFrame(SpikeMsg type, [List<int> payload = const []]) {
  final length = 1 + payload.length;
  if (length > spikeMaxFrame) throw ArgumentError('Frame too large: $length');
  final out = Uint8List(4 + length);
  ByteData.sublistView(out).setUint32(0, length);
  out[4] = type.code;
  out.setRange(5, 5 + payload.length, payload);
  return out;
}

Uint8List jsonPayload(Map<String, Object?> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// Reassembles frames from arbitrary TCP reads. One socket read is never
/// assumed to be one message.
class FrameReader {
  Uint8List _buf = Uint8List(64 * 1024);
  int _start = 0;
  int _end = 0;

  List<Frame> add(List<int> data) {
    _ensureRoom(data.length);
    _buf.setRange(_end, _end + data.length, data);
    _end += data.length;

    final frames = <Frame>[];
    while (true) {
      final available = _end - _start;
      if (available < 4) break;
      final length =
          ByteData.sublistView(_buf, _start, _start + 4).getUint32(0);
      if (length < 1 || length > spikeMaxFrame) {
        throw FormatException('Bad frame length $length');
      }
      if (available < 4 + length) break;
      final type = SpikeMsg.fromCode(_buf[_start + 4]);
      final payload = _buf.sublist(_start + 5, _start + 4 + length);
      frames.add(Frame(type, payload));
      _start += 4 + length;
    }
    if (_start == _end) {
      _start = 0;
      _end = 0;
    }
    return frames;
  }

  void _ensureRoom(int extra) {
    if (_end + extra <= _buf.length) return;
    final live = _end - _start;
    final needed = live + extra;
    if (needed <= _buf.length) {
      _buf.setRange(0, live, _buf, _start);
    } else {
      var capacity = _buf.length;
      while (capacity < needed) {
        capacity *= 2;
      }
      final bigger = Uint8List(capacity);
      bigger.setRange(0, live, _buf, _start);
      _buf = bigger;
    }
    _start = 0;
    _end = live;
  }
}

class ChannelClosed implements Exception {
  @override
  String toString() => 'ChannelClosed';
}

/// Frame-level wrapper around a socket with an awaitable `next()`.
class FrameChannel {
  FrameChannel(this.socket) {
    socket.listen(
      _onData,
      onError: _fail,
      onDone: () => _fail(ChannelClosed()),
      cancelOnError: true,
    );
  }

  final Socket socket;
  final FrameReader _reader = FrameReader();
  final Queue<Frame> _queue = Queue();
  final Completer<void> _closed = Completer<void>();
  Completer<Frame>? _waiter;
  Object? _error;

  Future<void> get closed => _closed.future;

  void _onData(Uint8List data) {
    try {
      for (final frame in _reader.add(data)) {
        final waiter = _waiter;
        if (waiter != null) {
          _waiter = null;
          waiter.complete(frame);
        } else {
          _queue.add(frame);
        }
      }
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object error) {
    _error ??= error;
    final waiter = _waiter;
    if (waiter != null) {
      _waiter = null;
      waiter.completeError(error);
    }
    if (!_closed.isCompleted) _closed.complete();
  }

  Future<Frame> next({Duration timeout = const Duration(seconds: 15)}) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeFirst());
    if (_error != null) return Future.error(_error!);
    final completer = Completer<Frame>();
    _waiter = completer;
    return completer.future.timeout(timeout, onTimeout: () {
      _waiter = null;
      throw TimeoutException('No frame within $timeout');
    });
  }

  void send(SpikeMsg type, [List<int> payload = const []]) =>
      socket.add(encodeFrame(type, payload));

  Future<void> close() async {
    socket.destroy();
  }
}
