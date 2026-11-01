import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../adapters/flutter_image_compressor.dart' show looksTruncated;
import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/format.dart';
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
  PlacementPlan? _plan;
  String? _contentId;
  String? _error;

  bool _picking = false;

  /// Picks an image and checks the copy is complete.
  ///
  /// The system photo picker occasionally hands over a cut-off copy (seen on one
  /// phone). If that happens, ask again through the plain file browser, which
  /// reads the file directly, before giving up.
  Future<void> _pick() async {
    if (_picking) return; // the system picker allows only one at a time
    setState(() => _picking = true);
    try {
      var path = await _pickOnce(FileType.image);
      if (path == null) return; // cancelled
      var problem = await _checkPicked(path);
      if (problem != null && mounted) {
        final retry = await _confirmRetry();
        if (retry == true) {
          final second = await _pickOnce(FileType.any, extensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic']);
          if (second != null) {
            path = second;
            problem = await _checkPicked(second);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _path = problem == null ? path : null;
        _stage = null;
        _job = null;
        _error = problem;
      });
    } on PlatformException {
      // Picker already open or closed by the system: nothing to do.
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<String?> _pickOnce(FileType type, {List<String>? extensions}) async {
    final picked = await FilePicker.pickFiles(
      type: type == FileType.any && extensions != null ? FileType.custom : type,
      allowedExtensions: type == FileType.any ? extensions : null,
    );
    if (picked.isEmpty) return null;
    return picked.first.path;
  }

  Future<bool?> _confirmRetry() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('That photo came through incomplete'),
          content: const Text(
            'The phone only gave HiveNet part of the file. Try again by choosing the same '
            'photo from the file browser instead?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choose again')),
          ],
        ),
      );

  Future<String?> _checkPicked(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (looksTruncated(bytes)) {
        return 'This photo is incomplete: the phone only provided part of the file. '
            'Pick it again, or choose a different photo.';
      }
      return null;
    } catch (_) {
      return 'That photo could not be read.';
    }
  }

  Future<void> _start() async {
    final rt = ref.read(runtimeProvider);
    if (rt == null || _path == null) return;
    setState(() {
      _running = true;
      _error = null;
      _stage = UploadStage.hashing;
      _job = null;
      _plan = null;
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
          _plan = u.plan ?? _plan;
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
                    child: Image.file(
                      File(_path!),
                      height: 200,
                      fit: BoxFit.cover,
                      // A preview that cannot be drawn must not stop the upload.
                      errorBuilder: (context, error, _) => Container(
                        height: 200,
                        alignment: Alignment.center,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Text('Preview not available for this image'),
                      ),
                    ),
                  ),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: (_running || _picking) ? null : _pick,
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
                  _Progress(
                    stage: _stage!,
                    job: _job,
                    running: _running,
                    progress: rt.uploadProgress,
                    nameOf: rt.nameOf,
                    describe: rt.describeFailure,
                  ),
                  if (_plan?.audit != null)
                    _Decision(audit: _plan!.audit!, nameOf: rt.nameOf),
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
  const _Progress({
    required this.stage,
    required this.job,
    required this.running,
    required this.progress,
    required this.nameOf,
    required this.describe,
  });

  final UploadStage stage;
  final UploadJob? job;
  final bool running;
  final ValueNotifier<Map<String, ({int sent, int total})>> progress;
  final String Function(String nodeId) nameOf;
  final String Function(String? reason) describe;

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
            if (running && stage != UploadStage.replicating)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.md),
                child: LinearProgressIndicator(),
              ),
            // One bar per storage device, with its name.
            ValueListenableBuilder(
              valueListenable: progress,
              builder: (context, map, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in map.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${nameOf(e.key)}  ·  ${formatBytes(e.value.sent)} of ${formatBytes(e.value.total)}',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: Spacing.xs),
                          LinearProgressIndicator(
                            value: e.value.total == 0 ? null : e.value.sent / e.value.total,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (state != null) ...[
              const SizedBox(height: Spacing.md),
              Align(alignment: Alignment.centerLeft, child: StatusChip.upload(state)),
            ],
            if (done && state != UploadState.completed && job?.failureReason != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(_reason(describe(job!.failureReason)), style: theme.textTheme.bodySmall),
              ),
            if (done && state != UploadState.completed)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  'HiveNet will not call this safe until the required copies are verified. '
                  'It keeps trying in the background whenever a paired phone is online, '
                  'or open Activity to retry now.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Turns the technical reason into sentences. Device names stay in.
  String _reason(String raw) {
    if (raw.contains('no eligible storage peers')) {
      return 'No paired phone was online with room to store a copy.';
    }
    final lines = <String>[];
    for (final part in raw.split('; ')) {
      final colon = part.indexOf(':');
      final who = colon > 0 ? part.substring(0, colon) : 'A device';
      final why = colon > 0 ? part.substring(colon + 1).trim() : part;
      if (why.contains('storage_full')) {
        lines.add('$who has no room left.');
      } else if (why.contains('timed out')) {
        lines.add('$who took too long to respond.');
      } else if (why.contains('unreachable') || why.contains('peer_disconnected')) {
        lines.add('$who could not be reached.');
      } else if (why.contains('hash verification')) {
        lines.add('$who stored data that failed verification, so it was not counted.');
      } else {
        lines.add('$who could not complete the transfer.');
      }
    }
    return lines.join(' ');
  }
}


/// Shows how the storage devices were chosen: the score of each one that
/// qualified, and why any others were skipped.
class _Decision extends StatelessWidget {
  const _Decision({required this.audit, required this.nameOf});

  final PlacementAudit audit;
  final String Function(String nodeId) nameOf;

  static String _why(IneligibleReason r) => switch (r) {
        IneligibleReason.notOnline => 'not online',
        IneligibleReason.staleTelemetry => 'no recent reading',
        IneligibleReason.overloaded => 'busy with other transfers',
        IneligibleReason.insufficientStorage => 'not enough free space',
        IneligibleReason.lowBattery => 'battery too low',
        IneligibleReason.notTrusted => 'not paired',
        IneligibleReason.incompatibleProtocol => 'different app version',
        IneligibleReason.excluded => 'this device',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How devices were chosen', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.xs),
              Text('Best score first. A device must be online, have room and enough battery.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: Spacing.sm),
              if (audit.ranking.isEmpty) const Text('No device qualified.'),
              for (final id in audit.ranking)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(audit.selected.contains(id) ? Icons.check_circle : Icons.circle_outlined,
                        size: Sizes.iconSm),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: Text(nameOf(id))),
                    Text('${audit.scores[id]!.total.round()} / 100'),
                  ]),
                ),
              for (final e in audit.rejected.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.remove_circle_outline, size: Sizes.iconSm, color: theme.colorScheme.outline),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text('${nameOf(e.key)}: skipped, ${e.value.map(_why).join(', ')}',
                          style: theme.textTheme.bodySmall),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
