import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 8: uploads and their honest outcome, with retry.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    final gallery = ref.watch(galleryProvider).asData?.value ?? const [];
    String nameOf(String? id) =>
        gallery.where((m) => m.contentId == id).firstOrNull?.fileName ?? 'Image';

    return jobs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyStateView(icon: Icons.error_outline, title: 'Could not load activity', message: '$e'),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
            child: Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyStateView(
                    icon: Icons.swap_vert,
                    title: 'No activity yet',
                    message: 'Uploads and their results will appear here.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(Spacing.lg),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
                    itemBuilder: (context, i) {
                      final j = list[i];
                      final inFlight = !j.status.isTerminal &&
                          j.status != UploadState.underReplicated &&
                          j.status != UploadState.retryPending &&
                          j.status != UploadState.created;
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(Spacing.md),
                          title: Text(nameOf(j.contentId)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: Spacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Upload · ${timeAgo(j.createdAt)}'),
                                const SizedBox(height: Spacing.sm),
                                StatusChip.upload(j.status),
                                if (inFlight)
                                  const Padding(
                                    padding: EdgeInsets.only(top: Spacing.sm),
                                    child: LinearProgressIndicator(),
                                  ),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/activity/${j.jobId}'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
