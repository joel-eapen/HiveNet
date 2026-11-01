import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/copyable_identifier.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/status_chip.dart';

class ActivityDetailsScreen extends ConsumerStatefulWidget {
  const ActivityDetailsScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ActivityDetailsScreen> createState() => _ActivityDetailsScreenState();
}

class _ActivityDetailsScreenState extends ConsumerState<ActivityDetailsScreen> {
  bool _retrying = false;
  String? _message;

  Future<void> _retry(String contentId) async {
    final rt = ref.read(runtimeProvider);
    if (rt == null) return;
    setState(() {
      _retrying = true;
      _message = null;
    });
    try {
      await for (final _ in rt.retryUpload(contentId)) {}
      _message = 'Finished. See the status above.';
    } catch (_) {
      _message = 'Could not retry. Check that your paired devices are online.';
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider).asData?.value ?? const [];
    final job = jobs.where((j) => j.jobId == widget.jobId).firstOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity details')),
      body: job == null
          ? const EmptyStateView(
              icon: Icons.swap_vert,
              title: 'Not found',
              message: 'This activity is no longer in the list.',
            )
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text('Upload', style: theme.textTheme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                Align(alignment: Alignment.centerLeft, child: StatusChip.upload(job.status)),
                const SizedBox(height: Spacing.lg),
                if (job.contentId != null) CopyableIdentifier(value: job.contentId!, label: 'Content ID'),
                const SizedBox(height: Spacing.md),
                Text('Wanted ${job.requestedReplicationFactor} verified copies · started ${timeAgo(job.createdAt)}'),
                if (job.failureReason != null) ...[
                  const SizedBox(height: Spacing.lg),
                  Text('What went wrong', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(job.failureReason!, style: theme.textTheme.bodySmall),
                ],
                if (job.contentId != null &&
                    (job.status == UploadState.underReplicated ||
                        job.status == UploadState.retryPending)) ...[
                  const SizedBox(height: Spacing.xl),
                  FilledButton.icon(
                    onPressed: _retrying ? null : () => _retry(job.contentId!),
                    icon: const Icon(Icons.replay),
                    label: Text(_retrying ? 'Retrying…' : 'Retry now'),
                  ),
                ],
                if (_message != null)
                  Padding(padding: const EdgeInsets.only(top: Spacing.md), child: Text(_message!)),
              ],
            ),
    );
  }
}
