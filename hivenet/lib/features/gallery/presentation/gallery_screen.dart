import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

enum _Filter { all, mine, shared, attention }

/// FR-12 screen 4. Entries only; no thumbnails are shown because a thumbnail is
/// image content and is not yet encrypted per viewer.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(galleryProvider);
    final me = ref.watch(runtimeProvider)?.identity.nodeId;
    final peers = ref.watch(peersProvider).asData?.value ?? const [];
    String owner(ImageManifest m) => m.ownerNodeId == me
        ? 'You'
        : peers.where((p) => p.nodeId == m.ownerNodeId).firstOrNull?.name ?? 'Another device';

    return gallery.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyStateView(
        icon: Icons.error_outline,
        title: 'Could not load the gallery',
        message: '$e',
        action: FilledButton(onPressed: () => ref.invalidate(galleryProvider), child: const Text('Retry')),
      ),
      data: (all) {
        final shown = all.where((m) {
          final okFilter = switch (_filter) {
            _Filter.all => true,
            _Filter.mine => m.ownerNodeId == me,
            _Filter.shared => m.ownerNodeId != me,
            _Filter.attention => m.availabilityStatus != AvailabilityStatus.available,
          };
          return okFilter && m.fileName.toLowerCase().contains(_query.toLowerCase());
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
              child: Text('Shared gallery', style: Theme.of(context).textTheme.headlineSmall),
            ),
            if (all.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
                child: Row(children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Spacing.sm),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => 'All',
                          _Filter.mine => 'Mine',
                          _Filter.shared => 'Shared with me',
                          _Filter.attention => 'Needs attention',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ]),
              ),
            ],
            Expanded(
              child: all.isEmpty
                  ? EmptyStateView(
                      icon: Icons.photo_library_outlined,
                      title: 'No images yet',
                      message: 'Upload an image to keep encrypted copies on your paired devices.',
                      action: FilledButton(
                        onPressed: () => context.push('/upload'),
                        child: const Text('Upload an image'),
                      ),
                    )
                  : shown.isEmpty
                      ? const EmptyStateView(
                          icon: Icons.search_off,
                          title: 'No matches',
                          message: 'Try a different search or filter.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(Spacing.lg),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
                          itemBuilder: (context, i) {
                            final m = shown[i];
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(Spacing.md),
                                leading: _Thumb(manifest: m, isMine: m.ownerNodeId == me),
                                title: Text(m.fileName),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: Spacing.sm),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${owner(m)} · ${formatBytes(m.fileSizeBytes)} · ${timeAgo(m.createdAt)}'),
                                      const SizedBox(height: Spacing.sm),
                                      Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
                                        StatusChip.availability(m.availabilityStatus),
                                        StatusChip.importance(m.importance),
                                      ]),
                                    ],
                                  ),
                                ),
                                onTap: () => context.push('/gallery/${m.contentId}'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}


/// Preview of this device's own image, or a lock for anyone else's. A thumbnail
/// is image content, so another device's picture is not shown without its key.
class _Thumb extends ConsumerWidget {
  const _Thumb({required this.manifest, required this.isMine});

  final ImageManifest manifest;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const size = 56.0;
    final rt = ref.watch(runtimeProvider);
    if (!isMine || rt == null) {
      return const SizedBox(width: size, height: size, child: Icon(Icons.lock_outline, size: Sizes.iconLg));
    }
    return FutureBuilder<String?>(
      future: rt.ownPreviewPath(manifest.contentId),
      builder: (context, snap) {
        final path = snap.data;
        if (path == null) {
          return const SizedBox(width: size, height: size, child: Icon(Icons.image_outlined, size: Sizes.iconLg));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: 160, // decode small: the list may hold many images
            errorBuilder: (_, _, _) => const SizedBox(
                width: size, height: size, child: Icon(Icons.broken_image_outlined, size: Sizes.iconLg)),
          ),
        );
      },
    );
  }
}
