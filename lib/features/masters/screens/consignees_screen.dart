import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/consignee.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class ConsigneesScreen extends ConsumerWidget {
  const ConsigneesScreen({super.key});

  static List<FormFieldSpec> _fields(Consignee? c) => [
        FormFieldSpec(
            name: 'name',
            label: 'Consignee Name',
            required: true,
            initialValue: c?.name),
        FormFieldSpec(
            name: 'gst',
            label: 'GST Number',
            required: true,
            initialValue: c?.gst,
            maxLength: 15),
        FormFieldSpec(
            name: 'location',
            label: 'Delivery Location',
            initialValue: c?.location),
        FormFieldSpec(
            name: 'address',
            label: 'Address',
            type: FieldType.multiline,
            initialValue: c?.address),
        FormFieldSpec(
            name: 'contact', label: 'Contact Person', initialValue: c?.contact),
        FormFieldSpec(
            name: 'mobile',
            label: 'Mobile',
            type: FieldType.number,
            maxLength: 12,
            initialValue: c?.mobile),
        FormFieldSpec(
            name: 'email',
            label: 'Email',
            type: FieldType.email,
            initialValue: c?.email),
      ];

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {Consignee? existing}) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Consignee' : 'Edit Consignee',
      subtitle: 'Searchable in LR entry',
      fields: _fields(existing),
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'gst': existing.gst,
              'location': existing.location,
              'address': existing.address,
              'contact': existing.contact,
              'mobile': existing.mobile,
              'email': existing.email,
            },
      onSave: (values) async {
        try {
          final n = ref.read(consigneesProvider.notifier);
          if (existing == null) {
            await n.add(Consignee(
              id: const Uuid().v4(),
              name: values['name'] ?? '',
              gst: values['gst'] ?? '',
              location: values['location'] ?? '',
              address: values['address'] ?? '',
              contact: values['contact'] ?? '',
              mobile: values['mobile'] ?? '',
              email: values['email'] ?? '',
            ));
          } else {
            await n.update(existing.copyWith(
              name: values['name'],
              gst: values['gst'],
              location: values['location'],
              address: values['address'],
              contact: values['contact'],
              mobile: values['mobile'],
              email: values['email'],
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
    final consignees = ref.watch(consigneesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Consignees',
      subtitle: '${consignees.length} delivery parties',
      icon: Icons.people_outline,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final c = consignees.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: c);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this consignee');
              if (!ok) return;
              try {
                await ref.read(consigneesProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const [
        'Name',
        'GST',
        'Delivery Location',
        'Contact',
        'Mobile',
      ],
      rows: [
        for (final c in consignees)
          MasterRow(
            id: c.id,
            cells: [c.name, c.gst, c.location, c.contact, c.mobile],
          ),
      ],
    );
  }
}
