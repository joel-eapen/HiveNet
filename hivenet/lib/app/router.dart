import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/devices/presentation/device_details_screen.dart';
import '../features/devices/presentation/devices_screen.dart';
import '../features/devices/presentation/pair_screen.dart';
import '../features/gallery/presentation/access_management_screen.dart';
import '../features/gallery/presentation/gallery_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/retrieval/presentation/image_details_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/storage_dashboard/presentation/storage_screen.dart';
import '../features/transfers/presentation/activity_details_screen.dart';
import '../features/transfers/presentation/activity_screen.dart';
import '../features/uploads/presentation/upload_screen.dart';
import '../shared/widgets/empty_state_view.dart';
import '../spike/spike_screen.dart';
import 'app_shell.dart';
import 'providers.dart';

abstract final class Routes {
  static const onboarding = '/onboarding';
  static const gallery = '/gallery';
  static const upload = '/upload';
  static const pair = '/pair';
  static const spike = '/spike';
}

/// The app's root navigator. Dialogs that must appear on top of any screen (a
/// pairing request) are shown through it.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirect when onboarding completes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(onboardingCompleteProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.gallery,
    refreshListenable: refresh,
    redirect: (context, state) {
      final done = ref.read(onboardingCompleteProvider);
      final atOnboarding = state.matchedLocation == Routes.onboarding;
      if (!done && !atOnboarding) return Routes.onboarding;
      if (done && atOnboarding) return Routes.gallery;
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: EmptyStateView(
        icon: Icons.error_outline,
        title: 'Page not found',
        message: 'There is nothing at ${state.uri}.',
        action: FilledButton(
          onPressed: () => context.go(Routes.gallery),
          child: const Text('Go to gallery'),
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(path: Routes.upload, builder: (_, _) => const UploadScreen()),
      GoRoute(path: Routes.pair, builder: (_, _) => const PairScreen()),
      // Milestone 0 developer spike; remove once the compatibility gate passes.
      GoRoute(path: Routes.spike, builder: (_, _) => const SpikeScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.gallery,
              builder: (_, _) => const GalleryScreen(),
              routes: [
                GoRoute(
                  path: ':contentId',
                  builder: (_, s) => ImageDetailsScreen(
                      contentId: s.pathParameters['contentId']!),
                  routes: [
                    GoRoute(
                      path: 'access',
                      builder: (_, s) => AccessManagementScreen(
                          contentId: s.pathParameters['contentId']!),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/activity',
              builder: (_, _) => const ActivityScreen(),
              routes: [
                GoRoute(
                  path: ':jobId',
                  builder: (_, s) =>
                      ActivityDetailsScreen(jobId: s.pathParameters['jobId']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/devices',
              builder: (_, _) => const DevicesScreen(),
              routes: [
                GoRoute(
                  path: ':nodeId',
                  builder: (_, s) =>
                      DeviceDetailsScreen(nodeId: s.pathParameters['nodeId']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/storage', builder: (_, _) => const StorageScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/settings', builder: (_, _) => const SettingsScreen()),
          ]),
        ],
      ),
    ],
  );
});
