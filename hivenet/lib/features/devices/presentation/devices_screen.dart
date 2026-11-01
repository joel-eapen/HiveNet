import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../demo/demo_data.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/placeholder_section.dart';
import '../../../shared/widgets/status_chip.dart';

/// FR-12 screen 3. A nearby, unpaired peer must never look trusted.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlaceholderHeader(title: 'Devices', prd: 'PRD FR-01, FR-02, FR-12'),
        Expanded(
          child: !demo
              ? EmptyStateView(
                  icon: Icons.devices_other_outlined,
                  title: 'No devices found',
                  message: 'Pair another phone to start sharing storage.',
                  action: FilledButton(
                    onPressed: () => context.push('/pair'),
                    child: const Text('Pair a device'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    for (final p in DemoData.peers)
                      Card(
                        child: ListTile(
                          title: Text(p.deviceName),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: Spacing.sm),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusChip.peer(p.status),
                            ),
                          ),
                          onTap: () => context.push('/devices/${p.nodeId}'),
                        ),
                      ),
                    const SizedBox(height: Spacing.md),
                    OutlinedButton(
                      onPressed: () => context.push('/pair'),
                      child: const Text('Pair a device'),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
