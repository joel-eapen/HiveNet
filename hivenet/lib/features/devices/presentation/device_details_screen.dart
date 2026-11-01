import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../demo/demo_data.dart';
import '../../../shared/widgets/copyable_identifier.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

class DeviceDetailsScreen extends ConsumerWidget {
  const DeviceDetailsScreen({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peer = ref.watch(demoModeProvider) ? DemoData.peerById(nodeId) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Device')),
      body: peer == null
          ? const EmptyStateView(
              icon: Icons.devices_other_outlined,
              title: 'Device not found',
              message: 'This device is not known to HiveNet.',
            )
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text(peer.deviceName,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip.peer(peer.status)),
                const SizedBox(height: Spacing.md),
                CopyableIdentifier(value: peer.nodeId, label: 'Node ID'),
              ],
            ),
    );
  }
}
