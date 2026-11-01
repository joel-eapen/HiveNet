import 'dart:convert';
import 'dart:typed_data';

import '../../shared/models/enums.dart';
import '../../shared/models/hive_error.dart';
import 'message_framing.dart';
import 'message_protocol.dart';
import 'network_config.dart';

/// Frame layout (all integers big-endian):
///
/// ```text
/// [u32 frameLength][u32 headerLength][header JSON, UTF-8][raw data bytes]
/// ```
///
/// `frameLength` counts everything after its own four bytes. The header is the
/// envelope's JSON; the optional raw data (chunk contents) follows it
/// unmodified.
class LengthPrefixedFraming implements MessageFraming {
  LengthPrefixedFraming({int? maxFrameBytes})
      : maxFrameBytes = maxFrameBytes ?? const NetworkConfig().maxFrameBytes;

  /// Largest accepted `frameLength`. Larger frames are rejected as soon as the
  /// length prefix is read, before any body is buffered.
  final int maxFrameBytes;

  @override
  Uint8List encode(MessageEnvelope message) {
    final header = utf8.encode(jsonEncode(message.toJson()));
    final data = message.data;
    final dataLength = data?.length ?? 0;
    final frameLength = 4 + header.length + dataLength;
    if (frameLength > maxFrameBytes) {
      throw HiveError(
        code: HiveErrorCode.oversizedMessage,
        message: 'Message is too large to send.',
        technicalDetails: 'frame $frameLength > limit $maxFrameBytes',
      );
    }
    final out = Uint8List(4 + frameLength);
    final view = ByteData.sublistView(out);
    view.setUint32(0, frameLength);
    view.setUint32(4, header.length);
    out.setRange(8, 8 + header.length, header);
    if (data != null) out.setRange(8 + header.length, out.length, data);
    return out;
  }

  /// Decodes a byte stream into messages. A malformed or oversized frame ends
  /// the stream with a [HiveError]; so does a connection that closes in the
  /// middle of a frame.
  @override
  Stream<MessageEnvelope> decode(Stream<List<int>> bytes) async* {
    final decoder = FrameDecoder(maxFrameBytes: maxFrameBytes);
    await for (final chunk in bytes) {
      for (final message in decoder.add(chunk)) {
        yield message;
      }
    }
    decoder.close();
  }
}

/// Incremental decoder. Feed it whatever the socket returns; it buffers partial
/// frames and splits coalesced ones, so one read is never assumed to be one
/// message.
///
/// After the first error the decoder is unusable and keeps rethrowing: once
/// framing is lost there is no safe way to find the next frame boundary.
class FrameDecoder {
  FrameDecoder({required this.maxFrameBytes});

  final int maxFrameBytes;

  Uint8List _buffer = Uint8List(64 * 1024);
  int _start = 0;
  int _end = 0;
  HiveError? _failure;

  /// True while some bytes of an unfinished frame are buffered.
  bool get hasPartialFrame => _end > _start;

  List<MessageEnvelope> add(List<int> incoming) {
    final failure = _failure;
    if (failure != null) throw failure;

    _reserve(incoming.length);
    _buffer.setRange(_end, _end + incoming.length, incoming);
    _end += incoming.length;

    final messages = <MessageEnvelope>[];
    try {
      while (true) {
        final available = _end - _start;
        if (available < 4) break;
        final frameLength =
            ByteData.sublistView(_buffer, _start, _start + 4).getUint32(0);
        // Validate the prefix before waiting for the body, so a hostile peer
        // cannot make us buffer an arbitrarily large frame.
        if (frameLength > maxFrameBytes) {
          throw HiveError(
            code: HiveErrorCode.oversizedMessage,
            message: 'A peer sent a message that is too large.',
            technicalDetails: 'frame $frameLength > limit $maxFrameBytes',
          );
        }
        if (frameLength < 4) {
          throw _malformed('frame length $frameLength is below the minimum');
        }
        if (available < 4 + frameLength) break;
        messages.add(_parse(_start + 4, frameLength));
        _start += 4 + frameLength;
      }
    } on HiveError catch (e) {
      _failure = e;
      rethrow;
    }

    if (_start == _end) {
      _start = 0;
      _end = 0;
    }
    return messages;
  }

  /// Call when the connection ends. Throws if a frame was cut off.
  void close() {
    final failure = _failure;
    if (failure != null) throw failure;
    if (hasPartialFrame) {
      throw _failure = _malformed('connection closed in the middle of a frame');
    }
  }

  MessageEnvelope _parse(int bodyStart, int frameLength) {
    final headerLength =
        ByteData.sublistView(_buffer, bodyStart, bodyStart + 4).getUint32(0);
    if (headerLength > frameLength - 4) {
      throw _malformed('header length exceeds the frame');
    }
    final headerStart = bodyStart + 4;
    final dataStart = headerStart + headerLength;
    final dataEnd = bodyStart + frameLength;
    try {
      final decoded = jsonDecode(
        utf8.decode(_buffer.sublist(headerStart, dataStart)),
      );
      if (decoded is! Map) throw const FormatException('header is not an object');
      final data = dataEnd > dataStart
          ? Uint8List.fromList(_buffer.sublist(dataStart, dataEnd))
          : null;
      return MessageEnvelope.fromJson(
        Map<String, Object?>.from(decoded),
        data: data,
      );
    } on HiveError {
      rethrow;
    } catch (e) {
      // FormatException, TypeError from a missing or mistyped field, and so on.
      throw _malformed('invalid header: $e');
    }
  }

  HiveError _malformed(String detail) => HiveError(
        code: HiveErrorCode.malformedMessage,
        message: 'A peer sent a message that could not be understood.',
        technicalDetails: detail,
      );

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
