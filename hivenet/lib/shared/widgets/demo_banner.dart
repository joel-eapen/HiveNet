import 'package:flutter/material.dart';

import '../../app/theme/spacing_tokens.dart';
import '../../app/theme/status_tone.dart';

/// Shown whenever fixture data is on screen so demo values are never mistaken
/// for live peer or storage state.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        color: StatusTone.warning.background(b),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.xs + 2),
        child: Row(
          children: [
            Icon(Icons.science_outlined,
                size: Sizes.iconSm, color: StatusTone.warning.foreground(b)),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'Demo data: not live peers or storage',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StatusTone.warning.foreground(b),
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
