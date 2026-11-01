import 'package:flutter/material.dart';

import '../../../shared/widgets/placeholder_section.dart';

/// FR-12 screen 6. Steps: select, importance and visibility, compression
/// preview, placement preview, progress. Success is shown as "Replicated" only
/// after all required replicas are verified.
class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload')),
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceholderHeader(title: 'Upload an image', prd: 'PRD FR-03, FR-04, FR-12'),
        ],
      ),
    );
  }
}
