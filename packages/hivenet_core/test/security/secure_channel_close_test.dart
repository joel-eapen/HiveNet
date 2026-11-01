import 'dart:typed_data';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:test/test.dart';

import '../helpers/net.dart';

void main() {
  test('a message sent just before close() is still delivered', () async {
    final alice = await TestDevice.create('alice');
    final bob = await TestDevice.create('bob');
    final pair = await SocketPair.open();
    addTearDown(pair.close);
    final ch = await handshake(pair, client: alice, server: bob);

    final received = ch.server.messages.toList();
    // Large enough that it cannot be written in one go; closing at once must not
    // throw the unsent part away. (This is how the last pairing message was lost.)
    await ch.client.send(MessageEnvelope(
      type: MessageType.heartbeat,
      requestId: 'last',
      senderNodeId: alice.nodeId,
      data: Uint8List(2 * 1024 * 1024),
    ));
    await ch.client.close();

    final messages = await received.timeout(const Duration(seconds: 10));
    expect(messages.map((m) => m.requestId), ['last']);
    expect(messages.single.data!.length, 2 * 1024 * 1024);
  });
}
