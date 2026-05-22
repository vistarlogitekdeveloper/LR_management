import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'My Profile',
            subtitle: user.role.label,
            actions: [
              AppButton(
                label: 'Logout',
                kind: BtnKind.ghost,
                icon: Icons.logout_rounded,
                onPressed: () {
                  ref.read(authProvider.notifier).logout();
                  context.go('/login');
                },
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor:
                              AppColors.plum.withValues(alpha: 0.12),
                          child: Text(
                            user.name.isEmpty
                                ? '?'
                                : user.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.plum,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '@${user.username}',
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.plum.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  user.role.label,
                                  style: const TextStyle(
                                    color: AppColors.plum,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.lock_outline_rounded,
                          title: 'Security',
                        ),
                        _ActionRow(
                          icon: Icons.password_rounded,
                          label: 'Change password',
                          onTap: () => context.go('/profile/change-password'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.assignment_ind_outlined,
                          title: 'Access scope',
                        ),
                        _AccessRow(
                          label: 'Create LR',
                          granted: user.role.canCreate,
                        ),
                        _AccessRow(
                          label: 'Edit LR',
                          granted: user.role.canEdit,
                        ),
                        _AccessRow(
                          label: 'Delete LR',
                          granted: user.role.canDelete,
                        ),
                        _AccessRow(
                          label: 'View Reports',
                          granted: user.role.canReports,
                        ),
                        _AccessRow(
                          label: 'Manage Masters',
                          granted: user.role.canMasters,
                        ),
                        _AccessRow(
                          label: 'Admin Panel',
                          granted: user.role.canAdmin,
                        ),
                      ],
                    ),
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

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: AppColors.plum, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
          ],
        ),
      ),
    );
  }
}

class _AccessRow extends StatelessWidget {
  final String label;
  final bool granted;
  const _AccessRow({required this.label, required this.granted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
          Icon(
            granted ? Icons.check_circle : Icons.cancel_outlined,
            size: 18,
            color: granted ? AppColors.ok : AppColors.slate,
          ),
        ],
      ),
    );
  }
}
