import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../demo/demo_data.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/placeholder_section.dart';

/// FR-12 screen 8.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlaceholderHeader(title: 'Activity', prd: 'PRD FR-12 (transfer activity)'),
        Expanded(
          child: !demo
              ? const EmptyStateView(
                  icon: Icons.swap_vert,
                  title: 'No activity yet',
                  message: 'Uploads, downloads and repairs will appear here.',
                )
              : ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    for (final t in DemoData.transfers)
                      Card(
                        child: ListTile(
                          title: Text('Upload · ${t.transferId}'),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: Spacing.sm),
                            child: LinearProgressIndicator(value: t.progress),
                          ),
                          onTap: () => context.push('/activity/${t.transferId}'),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
