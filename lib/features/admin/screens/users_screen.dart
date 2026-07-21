import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/admin_repository.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/users_provider.dart';
import '../widgets/user_permissions_dialog.dart';

class UsersAdminScreen extends ConsumerWidget {
  const UsersAdminScreen({super.key});

  static String _errorMessage(Object e) {
    if (e is DioException && e.error is ApiException) {
      return (e.error as ApiException).message;
    }
    if (e is ApiException) return e.message;
    return e.toString();
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    AppUser? existing,
  }) async {
    final currentUser = ref.read(currentUserProvider);
    final isSuper = currentUser?.isSuperAdmin ?? false;
    // Ensure roles are loaded before building the dialog (the screen also keeps
    // them warm). Awaiting the future removes the empty-picker race that left
    // the Role dropdown showing "No matches".
    List<RoleInfo> roles = const [];
    try {
      roles = await ref.read(rolesProvider.future);
    } catch (_) {
      // On failure leave roles empty — the picker shows "No matches".
    }
    if (!context.mounted) return;
    final roleNames = roles.map((r) => r.name).toList();
    final regions = ref.read(regionsProvider);
    final regionNames = regions.map((r) => r.name).toList();

    // Only pre-select a region the dropdown actually offers — otherwise the
    // DropdownButtonFormField would assert on an unknown value.
    final existingRegionName =
        (existing?.regionName != null &&
            regionNames.contains(existing!.regionName))
        ? existing.regionName
        : null;

    String? initialRoleName;
    if (existing != null) {
      initialRoleName = roles
          .where((r) => r.id == existing.roleId)
          .map((r) => r.name)
          .firstOrNull;
    }

    final messenger = ScaffoldMessenger.of(context);

    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New User' : 'Edit User',
      subtitle: 'System login credentials',
      fields: [
        FormFieldSpec(
          name: 'name',
          label: 'Full Name',
          required: true,
          initialValue: existing?.name,
        ),
        FormFieldSpec(
          name: 'username',
          label: 'Username',
          required: true,
          initialValue: existing?.username,
        ),
        FormFieldSpec(
          name: 'email',
          label: 'Email',
          type: FieldType.email,
          initialValue: existing?.email,
        ),
        FormFieldSpec(
          name: 'mobile',
          label: 'Mobile',
          initialValue: existing?.mobile,
        ),
        FormFieldSpec(
          name: 'role',
          label: 'Role',
          type: FieldType.dropdown,
          required: true,
          options: roleNames,
          initialValue: initialRoleName,
        ),
        // Region is assignable only by a super admin. Region admins create
        // users inside their own region automatically (set by the backend).
        if (isSuper)
          FormFieldSpec(
            name: 'region',
            label: 'Region (leave blank for super admins)',
            type: FieldType.dropdown,
            options: regionNames,
            initialValue: existingRegionName,
          ),
        FormFieldSpec(
          name: 'password',
          label: existing == null ? 'Password' : 'Reset Password (optional)',
          required: existing == null,
          initialValue: '',
        ),
      ],
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'username': existing.username,
              'email': existing.email,
              if (existing.mobile != null) 'mobile': existing.mobile!,
              'role': ?initialRoleName,
              'region': ?existingRegionName,
            },
      onSave: (values) async {
        final n = ref.read(usersProvider.notifier);
        final roleName = values['role'] ?? '';
        final role = roles.where((r) => r.name == roleName).firstOrNull;
        if (role == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Please select a valid role')),
          );
          return false;
        }
        final email = (values['email'] ?? '').trim();
        final mobile = (values['mobile'] ?? '').trim();

        // Resolve region (super admin only). Required for any non-super-admin
        // role so the new user is visible to their region admin.
        String? regionId;
        if (isSuper) {
          final regionName = (values['region'] ?? '').trim();
          regionId = regions
              .where((r) => r.name == regionName)
              .map((r) => r.id)
              .firstOrNull;
          final makingSuperAdmin = role.code == 'SUPER_ADMIN';
          if (!makingSuperAdmin && regionId == null) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Please pick a region for this user.'),
              ),
            );
            return false;
          }
        }

        try {
          if (existing == null) {
            await n.create(
              username: values['username'] ?? '',
              name: values['name'] ?? '',
              roleId: role.id,
              password: values['password'] ?? '',
              email: email.isEmpty ? null : email,
              mobile: mobile.isEmpty ? null : mobile,
              regionId: regionId,
              active: true,
            );
          } else {
            await n.updateUser(
              existing,
              name: values['name'] ?? existing.name,
              roleId: role.id,
              email: email,
              mobile: mobile.isEmpty ? null : mobile,
              regionId: regionId,
            );
          }
          return true;
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(_errorMessage(e))));
          return false;
        }
      },
    );
  }

  bool _canManagePermissions(AppUser? current, AppUser row) {
    if (current == null) return false;
    // Only admins / super admins manage per-user access (defense in depth; the
    // /admin route already gates this).
    if (!current.canAdmin) return false;
    // Never your own account — the backend rejects with SELF_LOCKOUT.
    if (current.id == row.id) return false;
    // Super-admin permissions are role-managed — the backend rejects with
    // SUPERADMIN_LOCKED, so never offer the entry point.
    if (row.role == UserRole.superAdmin) return false;
    // Only a super admin may restrict an ADMIN. Operators / accounts can be
    // managed by a super admin OR a regional admin (the backend enforces the
    // region scope and returns 403 on a cross-region edit).
    if (row.role == UserRole.admin) {
      return current.role == UserRole.superAdmin;
    }
    return row.role == UserRole.operator || row.role == UserRole.accounts;
  }

  Widget _userActions(
    BuildContext context,
    WidgetRef ref,
    AppUser? currentUser,
    AppUser u,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canManagePermissions(currentUser, u))
          IconButton(
            tooltip: 'Access',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.tune_rounded,
              color: AppColors.orange,
              size: 18,
            ),
            onPressed: () => UserPermissionsDialog.show(context, u),
          ),
        IconButton(
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.edit_outlined,
            color: AppColors.plum,
            size: 18,
          ),
          onPressed: () => _openForm(context, ref, existing: u),
        ),
        IconButton(
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.delete_outline,
            color: AppColors.danger,
            size: 18,
          ),
          onPressed: () => _deleteUser(context, ref, currentUser, u),
        ),
      ],
    );
  }

  Future<void> _deleteUser(
    BuildContext context,
    WidgetRef ref,
    AppUser? currentUser,
    AppUser u,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (currentUser != null && currentUser.id == u.id) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You cannot delete your own account.')),
      );
      return;
    }
    final ok = await showConfirmDialog(
      context: context,
      title: 'Delete user ${u.username}?',
      message: 'They will lose access to the system immediately.',
    );
    if (!ok) return;
    try {
      await ref.read(usersProvider.notifier).remove(u.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorMessage(e))));
    }
  }

  Widget _userMobileCard(
    BuildContext context,
    WidgetRef ref,
    AppUser? currentUser,
    AppUser u,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 14,
                  ),
                ),
              ),
              _RoleBadge(role: u.role),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '@${u.username}',
            style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Region: ',
                style: TextStyle(color: AppColors.slate, fontSize: 12),
              ),
              Text(
                u.regionName ?? '—',
                style: TextStyle(
                  color: u.regionName == null ? AppColors.slate : AppColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _userActions(context, ref, currentUser, u),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final usersLoading = ref.watch(usersLoadingProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isSuper = currentUser?.isSuperAdmin ?? false;
    // Keep regions AND roles warm for the form pickers. rolesProvider is an
    // autoDispose FutureProvider — without this watch it never loads before the
    // dialog reads it, so the Role picker came up empty ("No matches").
    ref.watch(regionsProvider);
    ref.watch(rolesProvider);

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Users',
            subtitle: isSuper
                ? '${users.length} users · all regions'
                : '${users.length} users · ${currentUser?.regionName ?? 'your region'}',
            actions: [
              AppButton(
                label: 'Add user',
                icon: Icons.person_add_alt_outlined,
                onPressed: () => _openForm(context, ref),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                MediaQuery.of(context).size.width < 600 ? 14 : 28,
              ),
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, c) {
                    // First load with nothing yet → shimmer, not "No users".
                    if (users.isEmpty && usersLoading) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: ShimmerRows(rows: 6),
                      );
                    }
                    if (users.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'No users',
                            style: TextStyle(color: AppColors.slate),
                          ),
                        ),
                      );
                    }
                    // Phones: stacked cards. Wider: the data table.
                    if (c.maxWidth < 640) {
                      return Column(
                        children: [
                          for (final u in users)
                            _userMobileCard(context, ref, currentUser, u),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          AppColors.plum.withValues(alpha: 0.05),
                        ),
                        columnSpacing: 28,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Username')),
                          DataColumn(label: Text('Role')),
                          DataColumn(label: Text('Region')),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (final u in users)
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    u.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                DataCell(Text(u.username)),
                                DataCell(_RoleBadge(role: u.role)),
                                DataCell(
                                  Text(
                                    u.regionName ?? '—',
                                    style: TextStyle(
                                      color: u.regionName == null
                                          ? AppColors.slate
                                          : AppColors.ink,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  _userActions(context, ref, currentUser, u),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final UserRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      UserRole.superAdmin => AppColors.red,
      UserRole.admin => AppColors.plum,
      UserRole.operator => AppColors.orange,
      UserRole.accounts => AppColors.ok,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
