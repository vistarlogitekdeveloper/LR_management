import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/driver.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  static List<FormFieldSpec> _fields(Driver? d) => [
        FormFieldSpec(
            name: 'name',
            label: 'Driver Name',
            required: true,
            initialValue: d?.name),
        FormFieldSpec(
            name: 'mobile',
            label: 'Mobile',
            required: true,
            type: FieldType.number,
            maxLength: 12,
            initialValue: d?.mobile),
        FormFieldSpec(
            name: 'licenseNo',
            label: 'License Number',
            required: true,
            initialValue: d?.licenseNo),
        FormFieldSpec(
            name: 'licenseExpiry',
            label: 'License Expiry (YYYY-MM-DD)',
            initialValue: d?.licenseExpiry),
        FormFieldSpec(
            name: 'address',
            label: 'Address',
            type: FieldType.multiline,
            initialValue: d?.address),
      ];

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {Driver? existing}) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Driver' : 'Edit Driver',
      subtitle: 'Driver master',
      fields: _fields(existing),
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'mobile': existing.mobile,
              'licenseNo': existing.licenseNo,
              'licenseExpiry': existing.licenseExpiry ?? '',
              'address': existing.address,
            },
      onSave: (values) async {
        try {
          final n = ref.read(driversProvider.notifier);
          if (existing == null) {
            await n.add(Driver(
              id: const Uuid().v4(),
              name: values['name'] ?? '',
              mobile: values['mobile'] ?? '',
              licenseNo: values['licenseNo'] ?? '',
              licenseExpiry: (values['licenseExpiry'] ?? '').isEmpty
                  ? null
                  : values['licenseExpiry'],
              address: values['address'] ?? '',
            ));
          } else {
            await n.update(existing.copyWith(
              name: values['name'],
              mobile: values['mobile'],
              licenseNo: values['licenseNo'],
              licenseExpiry: values['licenseExpiry'],
              address: values['address'],
            ));
          }
          return true;
        } catch (e) {
          MasterActions.showError(context, e);
          return false;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(driversProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Drivers',
      subtitle: '${drivers.length} drivers registered',
      icon: Icons.badge_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final d = drivers.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: d);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this driver');
              if (!ok) return;
              try {
                await ref.read(driversProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const [
        'Name',
        'Mobile',
        'License No',
        'License Expiry',
        'Address',
      ],
      rows: [
        for (final d in drivers)
          MasterRow(
            id: d.id,
            cells: [
              d.name,
              d.mobile,
              d.licenseNo,
              d.licenseExpiry ?? '—',
              d.address,
            ],
          ),
      ],
    );
  }
}
