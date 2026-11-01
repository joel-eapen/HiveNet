import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/runtime/hivenet_runtime.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';

/// FR-12 screen 9. Separates what this phone stores for others, what it keeps of
/// its own, and what can be cleared.
class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(storageStatsProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text('Storage', style: theme.textTheme.headlineSmall),
        const SizedBox(height: Spacing.sm),
        Text(
          'Contributing storage means holding encrypted copies. '
          'It does not let this device view them.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Spacing.lg),
        stats.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(Spacing.xl), child: CircularProgressIndicator())),
          error: (e, _) => Text('Could not read storage: $e'),
          data: (s) => s == null
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.md),
                    child: Text('Storage details appear once HiveNet is running.'),
                  ),
                )
              : _Details(s),
        ),
      ],
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details(this.s);
  final StorageStats s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final used = s.replicaBytes + s.reservedBytes;
    final fraction = s.quotaBytes == 0 ? 0.0 : (used / s.quotaBytes).clamp(0.0, 1.0);

    Widget row(IconData icon, String title, String value, [String? note]) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: note == null ? null : Text(note),
          trailing: Text(value, style: theme.textTheme.titleSmall),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shared with your devices', style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.sm),
                Text('${formatBytes(used)} of ${formatBytes(s.quotaBytes)}',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                LinearProgressIndicator(value: fraction, minHeight: 8),
                const SizedBox(height: Spacing.sm),
                Text(
                  '${s.replicaCount} encrypted ${s.replicaCount == 1 ? 'copy' : 'copies'} stored here'
                  '${s.reservedBytes > 0 ? ' · ${formatBytes(s.reservedBytes)} reserved for incoming uploads' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        row(Icons.lock_outline, 'Your uploaded originals', formatBytes(s.ownedBytes),
            'Encrypted copies kept on this phone'),
        row(Icons.pending_outlined, 'Unfinished transfers', formatBytes(s.partialBytes),
            'Kept so interrupted uploads can resume'),
        row(Icons.image_outlined, 'Opened images', formatBytes(s.cacheBytes),
            'Decrypted so they open quickly'),
        if (s.cacheBytes > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await ref.read(runtimeProvider)?.clearViewedCache();
                ref.invalidate(storageStatsProvider);
              },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear opened images'),
            ),
          ),
        const SizedBox(height: Spacing.md),
        Text(
          'Copies stored here are lost if the app is uninstalled or its data is cleared. '
          'HiveNet is not a backup: that is why every image keeps more than one copy.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
