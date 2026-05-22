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
  const AppSidebar({super.key, required this.currentLocation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final visibleSections = <NavSection>[];
    for (final section in AppNav.sections) {
      final filtered =
          section.items.where((i) => i.canAccess(user.role)).toList();
      if (filtered.isNotEmpty) {
        visibleSections
            .add(NavSection(title: section.title, items: filtered));
      }
    }

    return Container(
      width: 260,
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: const BrandLogo(height: 34),
          ),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              children: [
                for (final section in visibleSections) ...[
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(10, 14, 10, 6),
                    child: Text(
                      section.title.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  for (final item in section.items)
                    _SidebarTile(
                      item: item,
                      active: _isActive(item.path),
                      onTap: () => context.go(item.path),
                    ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.go('/profile'),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          AppColors.plum.withValues(alpha: 0.12),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user.role.label,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.slate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Logout',
                      onPressed: () {
                        ref.read(authProvider.notifier).logout();
                        context.go('/login');
                      },
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.slate),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  size: 18,
                  color: active ? AppColors.plum : AppColors.slate,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
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
