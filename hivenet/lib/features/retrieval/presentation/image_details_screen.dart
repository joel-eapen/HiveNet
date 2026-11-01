import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../demo/demo_data.dart';
import '../../../shared/widgets/copyable_identifier.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 5. Deep links must not bypass authorization: this screen will
/// fetch current metadata and permission state, and show a locked/denied view
/// (never a blank page) when access is refused.
class ImageDetailsScreen extends ConsumerWidget {
  const ImageDetailsScreen({super.key, required this.contentId});

  final String contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    final image = demo ? DemoData.imageById(contentId) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Image details')),
      body: image == null
          ? EmptyStateView(
              icon: Icons.lock_outline,
              title: 'Image not available',
              message:
                  'This image could not be found, or you do not have permission to see it.',
              action: CopyableIdentifier(value: contentId, label: 'Content ID'),
            )
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text(image.fileName,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                CopyableIdentifier(value: image.contentId, label: 'Content ID'),
                const SizedBox(height: Spacing.md),
                Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
                  StatusChip.availability(image.availabilityStatus),
                  StatusChip.importance(image.importance),
                  StatusChip.visibility(image.visibility),
                ]),
                const SizedBox(height: Spacing.lg),
                Text('Placeholder · PRD FR-08, FR-12: replicas, retrieval, access',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: Spacing.lg),
                OutlinedButton.icon(
                  onPressed: () => context.push('/gallery/$contentId/access'),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Manage access'),
                ),
              ],
            ),
    );
  }
}
