import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/consignor.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class ConsignorsScreen extends ConsumerWidget {
  const ConsignorsScreen({super.key});

  static List<FormFieldSpec> _fields(Consignor? c) => [
        FormFieldSpec(
            name: 'name',
            label: 'Consignor Name',
            required: true,
            initialValue: c?.name),
        FormFieldSpec(
            name: 'gst',
            label: 'GST Number',
            required: true,
            initialValue: c?.gst,
            maxLength: 15),
        FormFieldSpec(name: 'city', label: 'City', initialValue: c?.city),
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
      {Consignor? existing}) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Consignor' : 'Edit Consignor',
      subtitle: 'Auto-fills during LR entry',
      fields: _fields(existing),
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'gst': existing.gst,
              'city': existing.city,
              'address': existing.address,
              'contact': existing.contact,
              'mobile': existing.mobile,
              'email': existing.email,
            },
      onSave: (values) async {
        try {
          final n = ref.read(consignorsProvider.notifier);
          if (existing == null) {
            await n.add(Consignor(
              id: const Uuid().v4(),
              name: values['name'] ?? '',
              gst: values['gst'] ?? '',
              city: values['city'] ?? '',
              address: values['address'] ?? '',
              contact: values['contact'] ?? '',
              mobile: values['mobile'] ?? '',
              email: values['email'] ?? '',
            ));
          } else {
            await n.update(existing.copyWith(
              name: values['name'],
              gst: values['gst'],
              city: values['city'],
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
    final consignors = ref.watch(consignorsProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Consignors',
      subtitle: '${consignors.length} parties · auto-fill enabled',
      icon: Icons.business_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final c = consignors.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: c);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this consignor');
              if (!ok) return;
              try {
                await ref.read(consignorsProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const [
        'Name',
        'GST',
        'City',
        'Contact',
        'Mobile',
        'Email',
      ],
      rows: [
        for (final c in consignors)
          MasterRow(
            id: c.id,
            cells: [c.name, c.gst, c.city, c.contact, c.mobile, c.email],
          ),
      ],
    );
  }
}
