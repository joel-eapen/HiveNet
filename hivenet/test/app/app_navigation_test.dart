import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivenet/app/app.dart';
import 'package:hivenet/app/providers.dart';
import 'package:hivenet/app/router.dart';
import 'package:hivenet/demo/demo_data.dart';

class _Done extends OnboardingCompleteNotifier {
  @override
  bool build() => true;
}

Future<ProviderContainer> pumpApp(WidgetTester tester,
    {bool onboarded = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (onboarded) onboardingCompleteProvider.overrideWith(_Done.new),
      ],
      child: const HiveNetApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(HiveNetApp)));
}

void main() {
  testWidgets('first launch shows onboarding, then the gallery', (tester) async {
    await pumpApp(tester, onboarded: false);
    expect(find.text('Welcome to HiveNet'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Shared gallery'), findsOneWidget);
  });

  testWidgets('launches with the demo banner and an honest offline indicator',
      (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Demo data'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('each tab shows its screen', (tester) async {
    await pumpApp(tester);
    final tabs = {
      'Activity': 'Activity',
      'Devices': 'Devices',
      'Storage': 'Storage',
      'Settings': 'Settings',
      'Gallery': 'Shared gallery',
    };
    for (final entry in tabs.entries) {
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(entry.key)));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsWidgets, reason: entry.key);
    }
  });

  testWidgets('image details deep link renders', (tester) async {
    final c = await pumpApp(tester);
    final id = DemoData.images.first.contentId;
    c.read(routerProvider).go('/gallery/$id');
    await tester.pumpAndSettle();
    expect(find.text('Image details'), findsOneWidget);
    expect(find.text(DemoData.images.first.fileName), findsOneWidget);
  });

  testWidgets('unknown image shows a locked screen, not a blank page',
      (tester) async {
    final c = await pumpApp(tester);
    c.read(routerProvider).go('/gallery/doesnotexist');
    await tester.pumpAndSettle();
    expect(find.text('Image not available'), findsOneWidget);
  });

  testWidgets('access management and device details routes render',
      (tester) async {
    final c = await pumpApp(tester);
    final id = DemoData.images.first.contentId;
    c.read(routerProvider).go('/gallery/$id/access');
    await tester.pumpAndSettle();
    expect(find.text('Who can view this image'), findsOneWidget);
    expect(find.textContaining('cannot erase'), findsOneWidget);

    c.read(routerProvider).go('/devices/${DemoData.peers.first.nodeId}');
    await tester.pumpAndSettle();
    expect(find.text(DemoData.peers.first.deviceName), findsWidgets);
  });

  testWidgets('activity details, upload and pair routes render',
      (tester) async {
    final c = await pumpApp(tester);
    for (final (path, title) in [
      ('/activity/demo-transfer-1', 'Activity details'),
      ('/upload', 'Upload'),
      ('/pair', 'Pair a device'),
    ]) {
      c.read(routerProvider).go(path);
      await tester.pumpAndSettle();
      expect(find.text(title), findsWidgets, reason: path);
    }
  });

  testWidgets('unknown route shows the error screen', (tester) async {
    final c = await pumpApp(tester);
    c.read(routerProvider).go('/nope/nothing');
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);
  });

  testWidgets('deep links cannot skip onboarding', (tester) async {
    final c = await pumpApp(tester, onboarded: false);
    c.read(routerProvider).go('/gallery/abc');
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HiveNet'), findsOneWidget);
  });

  testWidgets('turning demo mode off removes fixture data', (tester) async {
    final c = await pumpApp(tester);
    c.read(demoModeProvider.notifier).set(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Demo data'), findsNothing);
    expect(find.text('No images yet'), findsOneWidget);
  });
}
