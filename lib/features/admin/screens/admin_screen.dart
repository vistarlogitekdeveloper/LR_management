import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shell/widgets/app_topbar.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final tiles = <_AdminTile>[
      const _AdminTile(
        title: 'Users',
        subtitle: 'Add, edit, deactivate accounts',
        icon: Icons.people_outline,
        path: '/admin/users',
        tint: AppColors.plum,
      ),
      if (user?.canManageRegions ?? false)
        const _AdminTile(
          title: 'Regions',
          subtitle: 'Operating areas & user assignments',
          icon: Icons.public_outlined,
          path: '/admin/regions',
          tint: AppColors.ok,
        ),
      const _AdminTile(
        title: 'LR Numbering',
        subtitle: 'Prefix, format & next number',
        icon: Icons.tag_rounded,
        path: '/admin/numbering',
        tint: AppColors.orange,
      ),
      const _AdminTile(
        title: 'LR Format',
        subtitle: 'Header, terms, footer & optional fields',
        icon: Icons.description_outlined,
        path: '/admin/lr-format',
        tint: AppColors.red,
      ),
      const _AdminTile(
        title: 'Audit Trail',
        subtitle: 'All system events with user & timestamp',
        icon: Icons.fact_check_outlined,
        path: '/admin/audit',
        tint: AppColors.amber,
      ),
      const _AdminTile(
        title: 'System Settings',
        subtitle: 'Backup, security & environment',
        icon: Icons.settings_outlined,
        path: '/admin/settings',
        tint: AppColors.plumLight,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'Admin Panel',
            subtitle: 'System administration',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 1100
                      ? 4
                      : c.maxWidth >= 700
                          ? 2
                          : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final t in tiles)
                        SizedBox(
                          width: (c.maxWidth - 16 * (cols - 1)) / cols,
                          child: t,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String path;
  final Color tint;

  const _AdminTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.path,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go(path),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 24, color: tint),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
