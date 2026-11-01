import 'package:flutter/material.dart';

import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/widgets/placeholder_section.dart';

/// FR-12 screen 9.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlaceholderHeader(title: 'Storage', prd: 'PRD FR-10, FR-12'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Text(
            'Contributing storage means holding encrypted copies. '
            'It does not let this device view them.',
          ),
        ),
      ],
    );
  }
}
