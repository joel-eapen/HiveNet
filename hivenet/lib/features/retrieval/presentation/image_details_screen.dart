import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../app/providers.dart';
import '../../../app/runtime/hivenet_runtime.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/copyable_identifier.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 5. Deep links never bypass checks: the entry is looked up in
/// local state, and the image opens only after it has been downloaded, hash
/// checked, decrypted and hash checked again.
class ImageDetailsScreen extends ConsumerStatefulWidget {
  const ImageDetailsScreen({super.key, required this.contentId});

  final String contentId;

  @override
  ConsumerState<ImageDetailsScreen> createState() => _ImageDetailsScreenState();
}

class _ImageDetailsScreenState extends ConsumerState<ImageDetailsScreen> {
  RetrievalSession? _session;
  bool _fetching = false;

  Future<void> _fetch() async {
    final rt = ref.read(runtimeProvider);
    if (rt == null || _fetching) return;
    setState(() {
      _fetching = true;
      _session = null;
    });
    try {
      await for (final s in rt.fetchImage(widget.contentId)) {
        if (!mounted) return;
        setState(() => _session = s);
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider).asData?.value ?? const [];
    final m = gallery.where((e) => e.contentId == widget.contentId).firstOrNull;
    final rt = ref.watch(runtimeProvider);

    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Image details')),
        body: EmptyStateView(
          icon: Icons.lock_outline,
          title: 'Image not available',
          message: 'This image could not be found, or you do not have permission to see it.',
          action: CopyableIdentifier(value: widget.contentId, label: 'Content ID'),
        ),
      );
    }

    final isOwner = rt != null && m.ownerNodeId == rt.identity.nodeId;
    final peers = ref.watch(peersProvider).asData?.value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Image details')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          _Preview(session: _session, fetching: _fetching, onFetch: rt == null ? null : _fetch),
          const SizedBox(height: Spacing.lg),
          Text(m.fileName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Spacing.xs),
          Text('${m.width}×${m.height} · ${formatBytes(m.fileSizeBytes)} · ${timeAgo(m.createdAt)}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.md),
          Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
            StatusChip.availability(m.availabilityStatus),
            StatusChip.importance(m.importance),
            StatusChip.visibility(m.visibility),
          ]),
          const SizedBox(height: Spacing.md),
          CopyableIdentifier(value: m.contentId, label: 'Content ID'),
          const SizedBox(height: Spacing.xl),
          Text('Where the copies are', style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            'Stored and online are different: a phone can hold a copy while its app is closed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Spacing.sm),
          _Replicas(contentId: m.contentId, wanted: m.desiredReplicationFactor, peers: peers),
          const SizedBox(height: Spacing.xl),
          if (isOwner)
            OutlinedButton.icon(
              onPressed: () => context.push('/gallery/${m.contentId}/access'),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Manage access'),
            )
          else
            Text('Owned by another device. Only the owner can change who can view it.',
                style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.session, required this.fetching, required this.onFetch});

  final RetrievalSession? session;
  final bool fetching;
  final VoidCallback? onFetch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;

    if (s?.stage == RetrievalStage.ready && s?.localPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: Image.file(
          File(s!.localPath!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, _) => const Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Text('This image was verified but could not be drawn on this device.'),
          ),
        ),
      );
    }

    String? message;
    IconData icon = Icons.lock_outline;
    switch (s?.stage) {
      case RetrievalStage.denied:
        message = 'You do not have permission to view this image.';
      case RetrievalStage.unavailable:
        message = 'No device holding a copy is online right now. Try again when one is.';
        icon = Icons.cloud_off_outlined;
      case RetrievalStage.failed:
        message = 'This image could not be opened.';
        icon = Icons.error_outline;
      case RetrievalStage.locatingReplica:
        message = 'Finding a device that has it…';
      case RetrievalStage.downloading:
        message = 'Downloading the encrypted copy…';
      case RetrievalStage.verifying:
        message = 'Checking it was not altered…';
      case RetrievalStage.decrypting:
        message = 'Decrypting on this phone…';
      default:
        message = null;
    }

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: Sizes.iconLg, color: theme.colorScheme.outline),
              if (message != null) ...[
                const SizedBox(height: Spacing.md),
                Text(message, textAlign: TextAlign.center),
              ],
              if (fetching) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    value: s?.stage == RetrievalStage.downloading ? s!.progress : null,
                  ),
                ),
              ] else ...[
                const SizedBox(height: Spacing.md),
                FilledButton.icon(
                  onPressed: onFetch,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(s == null ? 'View image' : 'Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Replicas extends ConsumerWidget {
  const _Replicas({required this.contentId, required this.wanted, required this.peers});

  final String contentId;
  final int wanted;
  final List<PeerView> peers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rt = ref.watch(runtimeProvider);
    if (rt == null) {
      return Text('0 of $wanted verified copies');
    }
    return FutureBuilder(
      future: rt.replicasOf(contentId),
      builder: (context, snap) {
        final rows = (snap.data ?? const []).where((r) => r.verified).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${rows.length} of $wanted verified copies',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            if (rows.isEmpty)
              const Text('No verified copy exists on another device yet.'),
            for (final r in rows)
              Builder(builder: (context) {
                final peer = peers.where((p) => p.nodeId == r.nodeId).firstOrNull;
                final online = peer?.status == PeerStatus.online;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smartphone),
                  title: Text(peer?.name ?? 'Another device'),
                  trailing: StatusChip.replica(
                      online ? ReplicaState.onlineServable : ReplicaState.temporarilyUnavailable),
                );
              }),
          ],
        );
      },
    );
  }
}
