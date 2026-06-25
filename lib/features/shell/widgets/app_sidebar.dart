import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/nav_items.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../auth/providers/auth_provider.dart';

class AppSidebar extends ConsumerWidget {
  final String currentLocation;

  /// Compact layout for the mobile drawer: narrower, tighter spacing and
  /// smaller type so it takes far less screen space. Tapping an item also
  /// closes the drawer.
  final bool compact;

  const AppSidebar({
    super.key,
    required this.currentLocation,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final visibleSections = <NavSection>[];
    for (final section in AppNav.sections) {
      final filtered = section.items.where((i) => i.canAccess(user)).toList();
      if (filtered.isNotEmpty) {
        visibleSections.add(NavSection(title: section.title, items: filtered));
      }
    }

    return Container(
      width: compact ? 224 : 260,
      color: AppColors.white,
      // SafeArea (top + bottom) keeps the logo below the status bar / clock and
      // the profile row above the system nav bar in the mobile drawer.
      child: SafeArea(
        left: false,
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: compact
                  ? const EdgeInsets.fromLTRB(16, 14, 16, 14)
                  : const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BrandLogo(height: compact ? 40 : 46),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 4 : 10,
                  horizontal: compact ? 8 : 12,
                ),
                children: [
                  for (final section in visibleSections) ...[
                    Padding(
                      padding: compact
                          ? const EdgeInsets.fromLTRB(10, 8, 10, 3)
                          : const EdgeInsets.fromLTRB(10, 14, 10, 6),
                      child: Text(
                        section.title.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.slate,
                          fontSize: compact ? 9.5 : 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final item in section.items)
                      _SidebarTile(
                        item: item,
                        active: _isActive(item.path),
                        compact: compact,
                        onTap: () {
                          context.go(item.path);
                          if (compact) Scaffold.maybeOf(context)?.closeDrawer();
                        },
                      ),
                  ],
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(compact ? 10 : 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  context.go('/profile');
                  if (compact) Scaffold.maybeOf(context)?.closeDrawer();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: compact ? 15 : 18,
                        backgroundColor: AppColors.plum.withValues(alpha: 0.12),
                        child: Text(
                          user.name.isNotEmpty
                              ? user.name.substring(0, 1).toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.plum,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 12.5 : 13,
                                color: AppColors.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user.regionName != null
                                  ? '${user.role.label} · ${user.regionName}'
                                  : user.role.label,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.slate,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Logout',
                        visualDensity: compact ? VisualDensity.compact : null,
                        onPressed: () {
                          ref.read(authProvider.notifier).logout();
                          context.go('/login');
                        },
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: AppColors.slate,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isActive(String path) {
    if (path == '/dashboard') return currentLocation == path;
    return currentLocation == path || currentLocation.startsWith('$path/');
  }
}

class _SidebarTile extends StatelessWidget {
  final NavItem item;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 1 : 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.plum.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: compact ? 17 : 18,
                  color: active ? AppColors.plum : AppColors.slate,
                ),
                SizedBox(width: compact ? 10 : 12),
                Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    fontSize: compact ? 13 : 13.5,
                    color: active ? AppColors.plum : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
