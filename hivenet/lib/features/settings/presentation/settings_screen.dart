import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/placeholder_section.dart';

/// FR-12 screen 10.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    return ListView(
      children: [
        const PlaceholderHeader(title: 'Settings', prd: 'PRD FR-12, section 10'),
        SwitchListTile(
          title: const Text('Show demo data'),
          subtitle: const Text('Fixture data for demos, clearly labelled.'),
          value: demo,
          onChanged: (v) => ref.read(demoModeProvider.notifier).set(v),
        ),
      ],
    );
  }
}
