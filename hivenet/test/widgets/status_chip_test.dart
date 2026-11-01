import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivenet/app/network_state.dart';
import 'package:hivenet/shared/widgets/status_chip.dart';
import 'package:hivenet/shared/widgets/status_style.dart';
import 'package:hivenet_core/hivenet_core.dart';

void main() {
  Future<void> expectTextAndIcon(WidgetTester tester, StatusStyle style) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StatusChip(style: style))),
    );
    expect(find.text(style.label), findsOneWidget, reason: style.label);
    expect(find.byIcon(style.icon), findsOneWidget, reason: style.label);
  }

  testWidgets('every status shows text and an icon', (tester) async {
    final styles = <StatusStyle>[
      for (final s in AvailabilityStatus.values) availabilityStyle(s),
      for (final s in ReplicaState.values) replicaStyle(s),
      for (final s in UploadState.values) uploadStyle(s),
      for (final s in PeerStatus.values) peerStyle(s),
      for (final s in NetworkState.values) networkStyle(s),
      for (final s in Importance.values) importanceStyle(s),
      for (final s in ImageVisibility.values) visibilityStyle(s),
    ];
    for (final style in styles) {
      await expectTextAndIcon(tester, style);
    }
  });

  test('completed and under-replicated uploads are worded differently', () {
    expect(uploadStyle(UploadState.completed).label, 'Replicated');
    expect(uploadStyle(UploadState.underReplicated).label,
        isNot('Replicated'));
  });

  test('stored and online replica states are distinct', () {
    expect(replicaStyle(ReplicaState.storedVerified).label,
        isNot(replicaStyle(ReplicaState.onlineServable).label));
  });
}
