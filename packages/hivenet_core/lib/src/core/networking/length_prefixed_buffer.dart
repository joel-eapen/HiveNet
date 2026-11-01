import 'dart:typed_data';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';

/// Splits a byte stream into `[u32 length][body]` frames, whatever the read
/// sizes. The length is checked as soon as its four bytes arrive, so a hostile
/// peer cannot make us buffer an oversized body.
///
/// After the first error the buffer keeps rethrowing: framing cannot be
/// recovered once a length is wrong.
class LengthPrefixedBuffer {
  LengthPrefixedBuffer({required this.maxBodyBytes});

  final int maxBodyBytes;

  Uint8List _buffer = Uint8List(64 * 1024);
  int _start = 0;
  int _end = 0;
  HiveError? _failure;

  bool get hasPartialFrame => _end > _start;

  List<Uint8List> add(List<int> incoming) {
    final failure = _failure;
    if (failure != null) throw failure;

    _reserve(incoming.length);
    _buffer.setRange(_end, _end + incoming.length, incoming);
    _end += incoming.length;

    final bodies = <Uint8List>[];
    while (_end - _start >= 4) {
      final length =
          ByteData.sublistView(_buffer, _start, _start + 4).getUint32(0);
      if (length > maxBodyBytes) {
        throw _failure = HiveError(
          code: HiveErrorCode.oversizedMessage,
          message: 'A peer sent a message that is too large.',
          technicalDetails: 'frame $length > limit $maxBodyBytes',
        );
      }
      if (_end - _start < 4 + length) break;
      bodies.add(_buffer.sublist(_start + 4, _start + 4 + length));
      _start += 4 + length;
    }
    if (_start == _end) {
      _start = 0;
      _end = 0;
    }
    return bodies;
  }

  /// Prefixes [body] with its length.
  static Uint8List frame(List<int> body) {
    final out = Uint8List(4 + body.length);
    ByteData.sublistView(out).setUint32(0, body.length);
    out.setRange(4, out.length, body);
    return out;
  }

  void _reserve(int extra) {
    if (_end + extra <= _buffer.length) return;
    final live = _end - _start;
    final needed = live + extra;
    if (needed <= _buffer.length) {
      _buffer.setRange(0, live, _buffer, _start);
    } else {
      var capacity = _buffer.length;
      while (capacity < needed) {
        capacity *= 2;
      }
      final bigger = Uint8List(capacity);
      bigger.setRange(0, live, _buffer, _start);
      _buffer = bigger;
    }
    _start = 0;
    _end = live;
  }
}
