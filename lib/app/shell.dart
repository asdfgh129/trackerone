import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = location.startsWith('/home/devices')
        ? 1
        : location.startsWith('/home/events')
            ? 2
            : location.startsWith('/home/tracking')
                ? 3
                : location.startsWith('/home/settings')
                    ? 4
                    : 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: l10n.mapTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.devices_other),
            selectedIcon: const Icon(Icons.devices),
            label: l10n.devicesTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_none),
            selectedIcon: const Icon(Icons.notifications),
            label: l10n.eventsTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.my_location),
            selectedIcon: const Icon(Icons.gps_fixed),
            label: l10n.trackingTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settingsTab,
          ),
        ],
      ),
    );
  }
}
