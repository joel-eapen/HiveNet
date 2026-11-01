import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/spacing_tokens.dart';

/// FR-12 screen 1. Skeleton: collects a device name and completes onboarding.
/// Real identity creation and the local-network permission request arrive in
/// Milestones 1 and 2.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(deviceNameProvider));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    ref.read(deviceNameProvider.notifier).set(name);
    ref.read(onboardingCompleteProvider.notifier).complete();
    context.go('/gallery');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.xl),
          children: [
            const SizedBox(height: Spacing.xl),
            Icon(Icons.hive_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: Spacing.lg),
            Text('Welcome to HiveNet', style: theme.textTheme.displaySmall),
            const SizedBox(height: Spacing.sm),
            Text(
              'Nearby phones share encrypted storage over your local network.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: Spacing.xl),
            const _Point(Icons.lock_outline,
                'Being on the same Wi-Fi does not give anyone access to your images.'),
            const _Point(Icons.storage_outlined,
                'This device can store encrypted copies. Storing a copy does not let it view the image.'),
            const _Point(Icons.tune,
                'You choose how much storage to contribute, and can contribute none.'),
            const SizedBox(height: Spacing.xl),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Device name',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(onPressed: _continue, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: Sizes.iconMd),
          const SizedBox(width: Spacing.md),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
