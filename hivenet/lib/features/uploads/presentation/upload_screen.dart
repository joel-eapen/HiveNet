import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 6: choose an image, importance and who can view it, then upload.
///
/// The result is worded from the real outcome. "Replicated" appears only when
/// every required copy was verified.
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String? _path;
  Importance _importance = Importance.normal;
  ImageVisibility _visibility = ImageVisibility.private;
  bool _running = false;
  UploadStage? _stage;
  UploadJob? _job;
  String? _contentId;
  String? _error;

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    setState(() {
      _path = picked.first.path;
      _stage = null;
      _job = null;
      _error = null;
    });
  }

  Future<void> _start() async {
    final rt = ref.read(runtimeProvider);
    if (rt == null || _path == null) return;
    setState(() {
      _running = true;
      _error = null;
      _stage = UploadStage.hashing;
      _job = null;
    });
    try {
      await for (final u in rt.uploadImage(
        sourcePath: _path!,
        importance: _importance,
        visibility: _visibility,
      )) {
        if (!mounted) return;
        setState(() {
          _stage = u.stage;
          _job = u.job ?? _job;
          _contentId = u.contentId ?? _contentId;
        });
      }
    } on HiveError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'The upload could not be completed. Nothing was shared.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = ref.watch(runtimeProvider);
    final theme = Theme.of(context);
    final finished = _stage == UploadStage.finished;
    return Scaffold(
      appBar: AppBar(title: const Text('Upload')),
      body: rt == null
          ? const Center(child: Text('HiveNet is not running on this device.'))
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text('Upload an image', style: theme.textTheme.headlineSmall),
                const SizedBox(height: Spacing.xs),
                Text(
                  'The image is shrunk and encrypted on this phone first. Other phones '
                  'only ever receive the encrypted copy.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Spacing.lg),
                if (_path != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Image.file(File(_path!), height: 200, fit: BoxFit.cover),
                  ),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: _running ? null : _pick,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_path == null ? 'Choose an image' : 'Choose a different image'),
                ),
                const SizedBox(height: Spacing.xl),
                Text('Importance', style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.sm),
                SegmentedButton<Importance>(
                  segments: const [
                    ButtonSegment(value: Importance.normal, label: Text('Normal · 2 copies')),
                    ButtonSegment(value: Importance.important, label: Text('Important · 3 copies')),
                  ],
                  selected: {_importance},
                  onSelectionChanged: _running ? null : (s) => setState(() => _importance = s.first),
                ),
                const SizedBox(height: Spacing.xl),
                Text('Who can view it', style: theme.textTheme.titleMedium),
                RadioGroup<ImageVisibility>(
                  groupValue: _visibility,
                  onChanged: (v) {
                    if (!_running && v != null) setState(() => _visibility = v);
                  },
                  child: const Column(children: [
                    RadioListTile(
                      value: ImageVisibility.private,
                      title: Text('Only me'),
                      subtitle: Text('Other phones store it but cannot open it.'),
                    ),
                    RadioListTile(
                      value: ImageVisibility.selectedDevices,
                      title: Text('Devices I choose'),
                      subtitle: Text('You pick them from the image page after uploading.'),
                    ),
                  ]),
                ),
                const SizedBox(height: Spacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Text(
                      'Storing a copy never lets a phone see the image. Only devices you '
                      'share it with receive the key.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: (_path == null || _running) ? null : _start,
                  child: Text(_running ? 'Uploading…' : (finished ? 'Upload again' : 'Upload')),
                ),
                if (_stage != null) ...[
                  const SizedBox(height: Spacing.xl),
                  _Progress(stage: _stage!, job: _job, running: _running),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.lg),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (finished && _contentId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.lg),
                    child: OutlinedButton(
                      onPressed: () => context.go('/gallery/$_contentId'),
                      child: const Text('Open in gallery'),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.stage, required this.job, required this.running});

  final UploadStage stage;
  final UploadJob? job;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = job?.status;
    final done = stage == UploadStage.finished;

    String headline;
    IconData icon;
    if (!done) {
      headline = switch (stage) {
        UploadStage.hashing => 'Preparing the image',
        UploadStage.encrypting => 'Encrypting on this phone',
        UploadStage.planning => 'Choosing storage devices',
        _ => 'Sending encrypted copies',
      };
      icon = Icons.hourglass_top;
    } else if (state == UploadState.completed) {
      headline = 'Replicated';
      icon = Icons.check_circle;
    } else if (state == UploadState.underReplicated) {
      headline = 'Uploaded, replication incomplete';
      icon = Icons.warning_amber_rounded;
    } else {
      headline = 'Pending: no copy is stored yet';
      icon = Icons.schedule;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: Spacing.sm),
              Expanded(child: Text(headline, style: theme.textTheme.titleMedium)),
            ]),
            if (running) const Padding(
              padding: EdgeInsets.only(top: Spacing.md),
              child: LinearProgressIndicator(),
            ),
            if (state != null) ...[
              const SizedBox(height: Spacing.md),
              Align(alignment: Alignment.centerLeft, child: StatusChip.upload(state)),
            ],
            if (done && state != UploadState.completed && job?.failureReason != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(_reason(job!.failureReason!), style: theme.textTheme.bodySmall),
              ),
            if (done && state != UploadState.completed)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  'HiveNet will not call this safe until the required copies are verified. '
                  'Open Activity to retry when more devices are online.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _reason(String raw) {
    if (raw.contains('no eligible storage peers')) {
      return 'No paired device was online to store a copy.';
    }
    if (raw.contains('storage_full')) return 'A device had no room left.';
    if (raw.contains('unreachable') || raw.contains('timed out')) {
      return 'A device could not be reached.';
    }
    return 'Some devices could not complete the transfer.';
  }
}
