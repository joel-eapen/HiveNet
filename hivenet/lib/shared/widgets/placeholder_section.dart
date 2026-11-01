import 'package:flutter/material.dart';

import '../../app/theme/spacing_tokens.dart';

/// Header for skeleton screens: what the screen is and which PRD requirement
/// it will implement.
class PlaceholderHeader extends StatelessWidget {
  const PlaceholderHeader({super.key, required this.title, required this.prd});

  final String title;
  final String prd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Spacing.xs),
          Text('Placeholder · $prd',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
