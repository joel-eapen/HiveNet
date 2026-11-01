import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/widgets/copyable_identifier.dart';

/// FR-12 screen 10.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rt = ref.watch(runtimeProvider);
    final name = ref.watch(deviceNameProvider);
    final demo = ref.watch(demoModeProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Text('Settings', style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: Spacing.md),
        ListTile(
          leading: const Icon(Icons.smartphone),
          title: const Text('Device name'),
          subtitle: Text(name),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _rename(context, ref, name),
        ),
        if (rt != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Spacing.sm),
                Text('This device\'s identity', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Compare this code with the one shown on another phone when pairing.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Spacing.sm),
                SelectableText(rt.identity.fingerprint,
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
                CopyableIdentifier(value: rt.identity.nodeId, label: 'Node ID'),
                FutureBuilder<String?>(
                  future: rt.localAddress(),
                  builder: (context, snap) => Text(
                    snap.data == null
                        ? 'Not connected to a network'
                        : 'Reachable at ${snap.data}:${rt.port}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const Divider(height: Spacing.xxl),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('How your images are protected'),
          subtitle: const Text(
              'Encrypted on this phone. Other phones store scrambled data and cannot open it unless you share.'),
        ),
        const Divider(height: Spacing.xxl),
        SwitchListTile(
          title: const Text('Show demo data'),
          subtitle: const Text('Fixture data for demos, clearly labelled.'),
          value: demo,
          onChanged: (v) => ref.read(demoModeProvider.notifier).set(v),
        ),
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Feasibility spike (developer)'),
          subtitle: const Text('Milestone 0 checks on real devices'),
          onTap: () => context.push('/spike'),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('HiveNet'),
          subtitle: Text('Version 1.0.0 · Android'),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device name'),
        content: TextField(controller: controller, autofocus: true, maxLength: 30),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      ref.read(deviceNameProvider.notifier).set(value);
    }
  }
}
