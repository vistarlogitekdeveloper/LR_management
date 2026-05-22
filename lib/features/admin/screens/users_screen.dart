import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/users_provider.dart';

class UsersAdminScreen extends ConsumerWidget {
  const UsersAdminScreen({super.key});

  static const _roles = ['Admin', 'Operator', 'Accounts'];

  static UserRole _roleFromLabel(String s) =>
      UserRole.values.firstWhere((r) => r.label == s,
          orElse: () => UserRole.operator);

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {AppUser? existing}) async {
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
            name: 'role',
            label: 'Role',
            type: FieldType.dropdown,
            required: true,
            options: _roles,
            initialValue: existing?.role.label),
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
              'role': existing.role.label,
            },
      onSave: (values) async {
        final n = ref.read(usersProvider.notifier);
        final role = _roleFromLabel(values['role'] ?? 'Operator');
        if (existing == null) {
          n.add(AppUser(
            username: values['username'] ?? '',
            password: values['password'] ?? '',
            role: role,
            name: values['name'] ?? '',
          ));
        } else {
          n.update(AppUser(
            username: existing.username,
            password: (values['password'] ?? '').isEmpty
                ? existing.password
                : values['password']!,
            role: role,
            name: values['name'] ?? existing.name,
          ));
        }
        return true;
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);

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
                                  final ok = await showConfirmDialog(
                                    context: context,
                                    title: 'Delete user ${u.username}?',
                                    message:
                                        'They will lose access to the system immediately.',
                                  );
                                  if (ok) {
                                    ref
                                        .read(usersProvider.notifier)
                                        .remove(u.username);
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
