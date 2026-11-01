import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../demo/demo_data.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/placeholder_section.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 4. Real gallery data comes from the manifest store in
/// Milestone 5. Entries here never show thumbnails (locked placeholder).
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlaceholderHeader(title: 'Shared gallery', prd: 'PRD FR-07, FR-12'),
        Expanded(
          child: !demo
              ? EmptyStateView(
                  icon: Icons.photo_library_outlined,
                  title: 'No images yet',
                  message: 'Upload an image to share it with your paired devices.',
                  action: FilledButton(
                    onPressed: () => context.push('/upload'),
                    child: const Text('Upload an image'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(Spacing.lg),
                  itemCount: DemoData.images.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
                  itemBuilder: (context, i) {
                    final image = DemoData.images[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(Spacing.md),
                        leading: const Icon(Icons.lock_outline, size: Sizes.iconLg),
                        title: Text(image.fileName),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: Spacing.sm),
                          child: Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: [
                              StatusChip.availability(image.availabilityStatus),
                              StatusChip.importance(image.importance),
                            ],
                          ),
                        ),
                        onTap: () => context.push('/gallery/${image.contentId}'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
