import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';

class MemoryKeyStore implements KeyStore {
  final Map<String, Uint8List> data = {};
  int writes = 0;
  Object? failReads;
  Object? failWrites;

  @override
  Future<Uint8List?> read(String name) async {
    if (failReads != null) throw failReads!;
    return data[name];
  }

  @override
  Future<void> write(String name, Uint8List value) async {
    if (failWrites != null) throw failWrites!;
    writes++;
    data[name] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String name) async => data.remove(name);
}
