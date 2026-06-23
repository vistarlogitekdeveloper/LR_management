import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/transporter.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class TransportersScreen extends ConsumerWidget {
  const TransportersScreen({super.key});

  static List<FormFieldSpec> _fields(Transporter? t) => [
        FormFieldSpec(
            name: 'name',
            label: 'Transporter Name',
            required: true,
            initialValue: t?.name),
        FormFieldSpec(
            name: 'pan',
            label: 'PAN',
            initialValue: t?.pan,
            required: true,
            maxLength: 10),
        FormFieldSpec(
            name: 'tds',
            label: 'TDS Applicable',
            type: FieldType.dropdown,
            options: const ['Yes', 'No'],
            initialValue: t?.tds ?? 'Yes'),
      ];

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {Transporter? existing}) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Transporter' : 'Edit Transporter',
      fields: _fields(existing),
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'pan': existing.pan,
              'tds': existing.tds,
            },
      onSave: (values) async {
        try {
          final n = ref.read(transportersProvider.notifier);
          if (existing == null) {
            await n.add(Transporter(
              id: const Uuid().v4(),
              name: values['name'] ?? '',
              pan: values['pan'] ?? '',
              tds: values['tds'] ?? 'No',
            ));
          } else {
            await n.update(existing.copyWith(
              name: values['name'],
              pan: values['pan'],
              tds: values['tds'],
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
    final transporters = ref.watch(transportersProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Transporter Master',
      subtitle: '${transporters.length} transporter partners',
      icon: Icons.alt_route_rounded,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final t = transporters.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: t);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this transporter');
              if (!ok) return;
              try {
                await ref.read(transportersProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const ['Name', 'PAN', 'TDS Applicable'],
      rows: [
        for (final t in transporters)
          MasterRow(id: t.id, cells: [t.name, t.pan, t.tds]),
      ],
    );
  }
}
