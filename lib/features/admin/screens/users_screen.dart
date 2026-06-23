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
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/admin_repository.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/users_provider.dart';

class UsersAdminScreen extends ConsumerWidget {
  const UsersAdminScreen({super.key});

  static String _errorMessage(Object e) {
    if (e is DioException && e.error is ApiException) {
      return (e.error as ApiException).message;
    }
    if (e is ApiException) return e.message;
    return e.toString();
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {AppUser? existing}) async {
    final roles = ref.read(rolesProvider).valueOrNull ?? const <RoleInfo>[];
    final roleNames = roles.map((r) => r.name).toList();

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
            initialValue: existing?.name),
        FormFieldSpec(
            name: 'username',
            label: 'Username',
            required: true,
            initialValue: existing?.username),
        FormFieldSpec(
            name: 'email',
            label: 'Email',
            type: FieldType.email,
            initialValue: existing?.email),
        FormFieldSpec(
            name: 'mobile',
            label: 'Mobile',
            initialValue: existing?.mobile),
        FormFieldSpec(
            name: 'role',
            label: 'Role',
            type: FieldType.dropdown,
            required: true,
            options: roleNames,
            initialValue: initialRoleName),
        FormFieldSpec(
            name: 'password',
            label: existing == null ? 'Password' : 'Reset Password (optional)',
            required: existing == null,
            initialValue: ''),
      ],
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'username': existing.username,
              'email': existing.email,
              if (existing.mobile != null) 'mobile': existing.mobile!,
              if (initialRoleName != null) 'role': initialRoleName,
            },
      onSave: (values) async {
        final n = ref.read(usersProvider.notifier);
        final roleName = values['role'] ?? '';
        final roleId = roles
            .where((r) => r.name == roleName)
            .map((r) => r.id)
            .firstOrNull;
        if (roleId == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Please select a valid role')),
          );
          return false;
        }
        final email = (values['email'] ?? '').trim();
        final mobile = (values['mobile'] ?? '').trim();
        try {
          if (existing == null) {
            await n.create(
              username: values['username'] ?? '',
              name: values['name'] ?? '',
              roleId: roleId,
              password: values['password'] ?? '',
              email: email.isEmpty ? null : email,
              mobile: mobile.isEmpty ? null : mobile,
              active: true,
            );
          } else {
            await n.updateUser(
              existing,
              name: values['name'] ?? existing.name,
              roleId: roleId,
              email: email,
              mobile: mobile.isEmpty ? null : mobile,
            );
          }
          return true;
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(_errorMessage(e))),
          );
          return false;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Users',
            subtitle: '${users.length} system users',
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
              padding: const EdgeInsets.all(28),
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
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
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final u in users)
                        DataRow(cells: [
                          DataCell(Text(u.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                          DataCell(Text(u.username)),
                          DataCell(_RoleBadge(role: u.role)),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined,
                                    color: AppColors.plum, size: 18),
                                onPressed: () =>
                                    _openForm(context, ref, existing: u),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.danger, size: 18),
                                onPressed: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  if (currentUser != null &&
                                      currentUser.id == u.id) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'You cannot delete your own account.')),
                                    );
                                    return;
                                  }
                                  final ok = await showConfirmDialog(
                                    context: context,
                                    title: 'Delete user ${u.username}?',
                                    message:
                                        'They will lose access to the system immediately.',
                                  );
                                  if (!ok) return;
                                  try {
                                    await ref
                                        .read(usersProvider.notifier)
                                        .remove(u.id);
                                  } catch (e) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(_errorMessage(e))),
                                    );
                                  }
                                },
                              ),
                            ],
                          )),
                        ]),
                    ],
                  ),
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
