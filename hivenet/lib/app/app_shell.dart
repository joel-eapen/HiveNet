import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/demo_banner.dart';
import '../shared/widgets/status_chip.dart';
import 'providers.dart';

/// Global shell: device name, network indicator, upload action, bottom
/// navigation (frontend PRD section 3). The indicator describes the peer
/// network, not internet connectivity.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceName = ref.watch(deviceNameProvider);
    final network = ref.watch(networkStateProvider);
    final demo = ref.watch(demoModeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('HiveNet'),
            Text(deviceName, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          StatusChip.network(network),
          IconButton(
            tooltip: 'Upload an image',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: () => context.push('/upload'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (demo) const DemoBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Gallery'),
          NavigationDestination(
              icon: Icon(Icons.swap_vert), label: 'Activity'),
          NavigationDestination(
              icon: Icon(Icons.devices_other_outlined),
              selectedIcon: Icon(Icons.devices_other),
              label: 'Devices'),
          NavigationDestination(
              icon: Icon(Icons.storage_outlined),
              selectedIcon: Icon(Icons.storage),
              label: 'Storage'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
