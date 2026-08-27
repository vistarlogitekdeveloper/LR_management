import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/in_flight_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/brand_logo.dart';
import 'widgets/app_sidebar.dart';

/// Chrome around the routed content: sidebar (or drawer on mobile), topbar,
/// and a hairline progress bar over the top edge of the content area.
///
/// The body is a [StatefulNavigationShell] — an IndexedStack under the hood —
/// so every branch (Dashboard, LR list, each master, etc.) is mounted at
/// most once and preserved forever after. Switching branches is a visibility
/// swap: no rebuild, no route transition, no re-fetch. That's what makes
/// sidebar taps feel instant even on Flutter web debug.
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;

    return Scaffold(
      backgroundColor: AppColors.mist,
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: AppColors.white,
              width: 224,
              child: AppSidebar(currentLocation: location, compact: true),
            ),
      appBar: isWide
          ? null
          : AppBar(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.ink,
              elevation: 0,
              shape: const Border(bottom: BorderSide(color: AppColors.line)),
              title: const BrandLogo(height: 30),
            ),
      body: Row(
        children: [
          if (isWide) AppSidebar(currentLocation: location),
          Expanded(
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(child: navigationShell),
                  // Overlay so page layout doesn't reflow when the bar shows —
                  // it just fades in/out over the top edge. Isolated in its
                  // own consumer so a busy-count flip doesn't rebuild the
                  // sidebar / drawer / topbar with it.
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopProgressBar(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline progress bar shown at the top of the content area whenever any
/// background refresh is in flight. Scoped to its own consumer so ticks of
/// [activeRefreshCountProvider] rebuild only this 2 px widget, not the whole
/// shell (sidebar + topbar).
class _TopProgressBar extends ConsumerWidget {
  const _TopProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(activeRefreshCountProvider) > 0;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: busy ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: const SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.plum),
          ),
        ),
      ),
    );
  }
}
