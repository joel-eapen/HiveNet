import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/widgets/empty_state_view.dart';

/// FR-12 screen 7, FR-09A. Keeps three permissions apart in plain words: holding
/// an encrypted copy, fetching it, and being able to open it.
class AccessManagementScreen extends ConsumerStatefulWidget {
  const AccessManagementScreen({super.key, required this.contentId});

  final String contentId;

  @override
  ConsumerState<AccessManagementScreen> createState() => _AccessManagementScreenState();
}

class _AccessManagementScreenState extends ConsumerState<AccessManagementScreen> {
  final Set<String> _busy = {};
  String? _error;

  Future<void> _toggle(String nodeId, bool share) async {
    final rt = ref.read(runtimeProvider);
    if (rt == null) return;
    if (!share) {
      final ok = await _confirmRevoke();
      if (ok != true) return;
    }
    setState(() {
      _busy.add(nodeId);
      _error = null;
    });
    try {
      if (share) {
        await rt.shareImage(widget.contentId, nodeId);
      } else {
        await rt.unshareImage(widget.contentId, nodeId);
      }
    } on HiveError catch (e) {
      _error = share
          ? 'Could not share. The other phone must be online. (${e.message})'
          : e.message;
    } catch (_) {
      _error = share
          ? 'Could not reach that phone. It must be online to receive access.'
          : 'Something went wrong.';
    } finally {
      if (mounted) setState(() => _busy.remove(nodeId));
    }
  }

  Future<bool?> _confirmRevoke() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop sharing?'),
          content: const Text(
            'Future requests from this device will be refused.\n\n'
            'HiveNet cannot take back a copy this device already downloaded or a key it '
            'already received. A storage phone that is offline keeps honouring the old '
            'permission until it hears about the change.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop sharing')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rt = ref.watch(runtimeProvider);
    final peers = (ref.watch(peersProvider).asData?.value ?? const []).where((p) => p.paired).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Access')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Text('Who can view this image', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Legend(Icons.save_alt, 'Can store an encrypted copy',
                      'Holds scrambled data. Cannot open it.'),
                  _Legend(Icons.download, 'Can fetch the encrypted copy',
                      'Gets the same scrambled data. Still cannot open it.'),
                  _Legend(Icons.visibility, 'Can view',
                      'Has the key. Only you decide this, per image and per device.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          // Stated up front, not buried: revocation has limits.
          Text(
            'Revoking access blocks future requests and key deliveries. '
            'It cannot erase a copy that someone already downloaded.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Spacing.lg),
          if (rt == null || peers.isEmpty)
            const EmptyStateView(
              icon: Icons.devices_other_outlined,
              title: 'No paired devices',
              message: 'Pair a device first, then you can share this image with it.',
            )
          else
            FutureBuilder(
              future: rt.policy.grantsFor(widget.contentId),
              builder: (context, snap) {
                final grants = snap.data ?? const <AccessGrant>[];
                bool canView(String id) => grants.any((g) =>
                    g.granteeNodeId == id &&
                    g.permission == PermissionType.view &&
                    g.isActiveAt(DateTime.now()));
                return Column(children: [
                  for (final p in peers)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(_busy.contains(p.nodeId)
                          ? 'Working…'
                          : (canView(p.nodeId) ? 'Can view this image' : 'Cannot view this image')),
                      value: canView(p.nodeId),
                      onChanged: _busy.contains(p.nodeId) ? null : (v) => _toggle(p.nodeId, v),
                    ),
                ]);
              },
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: Sizes.iconMd),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      );
}
