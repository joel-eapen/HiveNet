import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/runtime/hivenet_runtime.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 3. A nearby device that is not paired is never shown as trusted.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(peersProvider);
    return peers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyStateView(
        icon: Icons.error_outline,
        title: 'Could not load devices',
        message: '$e',
      ),
      data: (list) {
        final paired = list.where((p) => p.paired).toList();
        final nearby = list.where((p) => !p.paired).toList();
        return ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Text('Devices', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              'Paired devices store encrypted copies for you. '
              'Being on the same Wi-Fi gives a device no access.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton.icon(
              onPressed: () => context.push('/pair'),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Pair a device'),
            ),
            const SizedBox(height: Spacing.xl),
            Text('Paired', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (paired.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: EmptyStateView(
                  icon: Icons.devices_other_outlined,
                  title: 'No paired devices',
                  message: 'Pair another phone to start sharing storage.',
                ),
              ),
            for (final p in paired) _DeviceCard(peer: p),
            if (nearby.isNotEmpty) ...[
              const SizedBox(height: Spacing.xl),
              Text('Nearby, not paired', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.xs),
              Text(
                'Seen on this network. They cannot use your storage or see your images until you pair.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Spacing.sm),
              for (final p in nearby) _DeviceCard(peer: p),
            ],
          ],
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.peer});
  final PeerView peer;

  @override
  Widget build(BuildContext context) {
    final t = peer.telemetry;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(Spacing.md),
          leading: const Icon(Icons.smartphone, size: Sizes.iconLg),
          title: Text(peer.name),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip.peer(peer.status),
                if (peer.paired && t != null) ...[
                  const SizedBox(height: Spacing.sm),
                  Text('${formatBytes(t.availableStorageBytes)} free of '
                      '${formatBytes(t.totalStorageBytes)} shared'
                      '${t.measuredLatencyMs == null ? '' : ' · ${t.measuredLatencyMs} ms'}'),
                ],
                if (peer.paired)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: Text('Last seen ${timeAgo(peer.lastSeen)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (peer.problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Row(children: [
                      Icon(Icons.link_off, size: Sizes.iconSm, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text('Cannot connect. Tap to pair again.',
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
          trailing: peer.paired ? const Icon(Icons.chevron_right) : null,
          onTap: peer.paired ? () => context.push('/devices/${peer.nodeId}') : null,
        ),
      ),
    );
  }
}
