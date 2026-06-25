import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/party.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class PartiesScreen extends ConsumerWidget {
  const PartiesScreen({super.key});

  static List<FormFieldSpec> _fields(Party? p) => [
    FormFieldSpec(
      name: 'name',
      label: 'Party Name',
      required: true,
      initialValue: p?.name,
    ),
    FormFieldSpec(
      name: 'gst',
      label: 'GST Number',
      required: true,
      initialValue: p?.gst,
      maxLength: 15,
    ),
    FormFieldSpec(name: 'city', label: 'City', initialValue: p?.city),
    FormFieldSpec(
      name: 'address',
      label: 'Address',
      type: FieldType.multiline,
      initialValue: p?.address,
    ),
    FormFieldSpec(
      name: 'contact',
      label: 'Contact Person',
      initialValue: p?.contact,
    ),
    FormFieldSpec(
      name: 'mobile',
      label: 'Mobile',
      type: FieldType.number,
      maxLength: 12,
      initialValue: p?.mobile,
    ),
    FormFieldSpec(
      name: 'email',
      label: 'Email',
      type: FieldType.email,
      initialValue: p?.email,
    ),
  ];

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Party? existing,
  }) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Party' : 'Edit Party',
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
          final n = ref.read(partiesProvider.notifier);
          if (existing == null) {
            await n.add(
              Party(
                id: const Uuid().v4(),
                name: values['name'] ?? '',
                gst: values['gst'] ?? '',
                city: values['city'] ?? '',
                address: values['address'] ?? '',
                contact: values['contact'] ?? '',
                mobile: values['mobile'] ?? '',
                email: values['email'] ?? '',
              ),
            );
          } else {
            await n.update(
              existing.copyWith(
                name: values['name'],
                gst: values['gst'],
                city: values['city'],
                address: values['address'],
                contact: values['contact'],
                mobile: values['mobile'],
                email: values['email'],
              ),
            );
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
    final parties = ref.watch(partiesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageParties ?? false;

    return MasterPage(
      title: 'Parties',
      subtitle: '${parties.length} parties · auto-fill enabled',
      icon: Icons.business_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final p = parties.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: p);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                context: context,
                label: 'this party',
              );
              if (!ok) return;
              try {
                await ref.read(partiesProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const ['Name', 'GST', 'City', 'Contact', 'Mobile', 'Email'],
      rows: [
        for (final p in parties)
          MasterRow(
            id: p.id,
            cells: [p.name, p.gst, p.city, p.contact, p.mobile, p.email],
          ),
      ],
    );
  }
}
