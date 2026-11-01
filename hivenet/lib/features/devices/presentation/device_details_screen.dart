import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/copyable_identifier.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

class DeviceDetailsScreen extends ConsumerWidget {
  const DeviceDetailsScreen({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(peersProvider).asData?.value ?? const [];
    final peer = peers.where((p) => p.nodeId == nodeId).firstOrNull;
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
                Text(peer.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                Align(alignment: Alignment.centerLeft, child: StatusChip.peer(peer.status)),
                const SizedBox(height: Spacing.lg),
                CopyableIdentifier(value: peer.nodeId, label: 'Node ID'),
                const SizedBox(height: Spacing.md),
                _Row('Last seen', timeAgo(peer.lastSeen)),
                if (peer.telemetry != null) ...[
                  _Row('Shared storage', formatBytes(peer.telemetry!.totalStorageBytes)),
                  _Row('Free', formatBytes(peer.telemetry!.availableStorageBytes)),
                  if (peer.telemetry!.measuredLatencyMs != null)
                    _Row('Latency', '${peer.telemetry!.measuredLatencyMs} ms'),
                ],
                if (peer.host != null) _Row('Address', '${peer.host}:${peer.port}'),
                const SizedBox(height: Spacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Text(
                      'This device can store encrypted copies of your images. It cannot open '
                      'them unless you share a specific image with it.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                if (peer.paired) ...[
                  const SizedBox(height: Spacing.xl),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => _confirmRevoke(context, ref),
                    icon: const Icon(Icons.block),
                    label: const Text('Remove this device'),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this device?'),
        content: const Text(
          'It will no longer be able to connect, store copies for you or fetch your images.\n\n'
          'Copies it already holds stay on that phone until it is cleared, and anything it '
          'already opened or downloaded cannot be taken back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(runtimeProvider)?.revokeDevice(nodeId);
    if (context.mounted) context.go('/devices');
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Flexible(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      );
}
