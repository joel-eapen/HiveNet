import 'package:flutter/material.dart';

import '../../../shared/widgets/placeholder_section.dart';

class ActivityDetailsScreen extends StatelessWidget {
  const ActivityDetailsScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity details')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceholderHeader(title: 'Job $jobId', prd: 'PRD FR-12, section 13.1'),
        ],
      ),
    );
  }
}
