import 'package:flutter/material.dart';

import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/widgets/placeholder_section.dart';

/// FR-12 screen 7, FR-09A. Must keep three permissions distinct in the UI:
/// store encrypted copy, retrieve ciphertext, view/decrypt. Revocation text
/// must not promise remote erasure.
class AccessManagementScreen extends StatelessWidget {
  const AccessManagementScreen({super.key, required this.contentId});

  final String contentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access')),
      body: ListView(
        children: const [
          PlaceholderHeader(title: 'Who can view this image', prd: 'PRD FR-09A, FR-09B'),
          Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Text(
              'Revoking access blocks future requests and key deliveries. '
              'It cannot erase a copy that someone already downloaded.',
            ),
          ),
        ],
      ),
    );
  }
}
