import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:hivenet_core/hivenet_core.dart';

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
                if (peer.problem != null) ...[
                  const SizedBox(height: Spacing.md),
                  _ProblemCard(
                    text: peer.problem!,
                    onPairAgain: () => context.push('/pair'),
                  ),
                ],
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
                if (peer.paired && peer.telemetry != null) ...[
                  const SizedBox(height: Spacing.lg),
                  _ScoreCard(telemetry: peer.telemetry!, breakdown: ref.read(runtimeProvider)?.scoreOf(peer.nodeId)),
                ],
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


class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.text, required this.onPairAgain});
  final String text;
  final VoidCallback onPairAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.link_off, color: scheme.onErrorContainer),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Cannot connect',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onErrorContainer)),
              ),
            ]),
            const SizedBox(height: Spacing.sm),
            Text(text, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: Spacing.sm),
            FilledButton(onPressed: onPairAgain, child: const Text('Pair again')),
          ],
        ),
      ),
    );
  }
}

/// How HiveNet rates this device as a place to keep a copy, and why. The same
/// numbers decide which devices an upload uses: higher is better.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.telemetry, required this.breakdown});

  final PeerTelemetry telemetry;
  final ScoreBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = breakdown;
    if (b == null) return const SizedBox.shrink();

    String? detail(String key) {
      switch (key) {
        case 'Storage':
          return '${formatBytes(telemetry.availableStorageBytes)} free';
        case 'Speed':
          return telemetry.measuredLatencyMs == null ? 'not measured' : '${telemetry.measuredLatencyMs} ms';
        case 'Battery':
          if (telemetry.batteryPercent == null) return 'unknown';
          return '${telemetry.batteryPercent}%${telemetry.isCharging == true ? ', charging' : ''}';
        case 'Reliability':
          final r = telemetry.reliabilityScore;
          return r == null ? 'still measuring' : '${r.round()}% of checks answered';
        case 'Load':
          return '${telemetry.activeTransfers} active ${telemetry.activeTransfers == 1 ? 'transfer' : 'transfers'}';
      }
      return null;
    }

    final rows = <(String, double)>[
      ('Storage', b.capacity),
      ('Speed', b.latency),
      ('Battery', b.battery),
      ('Reliability', b.uptime),
      ('Load', b.load),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Storage suitability', style: theme.textTheme.titleMedium),
                Text('${b.total.round()} / 100', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Uploads use the highest-scoring online devices.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.md),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: theme.textTheme.bodySmall),
                        Text(detail(label) ?? '', style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 2),
                    LinearProgressIndicator(value: value / 100, minHeight: 6),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
