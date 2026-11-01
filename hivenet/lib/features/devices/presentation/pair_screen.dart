import 'package:flutter/material.dart';

import '../../../shared/widgets/placeholder_section.dart';

/// FR-12 screen 2. QR pairing plus a manual IP/port diagnostic fallback.
/// Both devices must show the fingerprint and require explicit confirmation.
class PairScreen extends StatelessWidget {
  const PairScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a device')),
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceholderHeader(title: 'Pair a device', prd: 'PRD FR-01 (QR + manual fallback)'),
        ],
      ),
    );
  }
}
