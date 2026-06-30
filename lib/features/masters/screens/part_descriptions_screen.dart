import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/part_description.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lookups/data/lookup_value.dart';
import '../../lookups/providers/lookups_provider.dart';
import '../providers/part_descriptions_provider.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

const _none = '(None)';

class PartDescriptionsScreen extends ConsumerWidget {
  const PartDescriptionsScreen({super.key});

  static List<FormFieldSpec> _fields(
    PartDescription? p, {
    required List<String> packageTypes,
  }) =>
      [
        FormFieldSpec(
            name: 'name',
            label: 'Name',
            required: true,
            initialValue: p?.name),
        FormFieldSpec(
            name: 'nature_of_goods',
            label: 'Nature of Goods',
            initialValue: p?.natureOfGoods),
        FormFieldSpec(
            name: 'default_package_type',
            label: 'Default Package Type',
            type: FieldType.dropdown,
            options: [_none, ...packageTypes],
            initialValue: (p?.defaultPackageTypeLabel?.isNotEmpty ?? false)
                ? p!.defaultPackageTypeLabel
                : _none),
        FormFieldSpec(
            name: 'active',
            label: 'Status',
            type: FieldType.dropdown,
            required: true,
            options: const ['Active', 'Inactive'],
            initialValue: (p?.active ?? true) ? 'Active' : 'Inactive'),
      ];

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    PartDescription? existing,
    required List<LookupValue> packageTypes,
  }) async {
    final typeLabels = packageTypes.map((e) => e.label).toList();

    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Part Description' : 'Edit Part Description',
      subtitle: 'Auto-fills Nature of Goods & Package Type during LR entry',
      fields: _fields(existing, packageTypes: typeLabels),
      initial: existing == null
          ? const {}
          : {
              'name': existing.name,
              'nature_of_goods': existing.natureOfGoods ?? '',
              'default_package_type':
                  existing.defaultPackageTypeLabel?.isNotEmpty ?? false
                      ? existing.defaultPackageTypeLabel!
                      : _none,
              'active': existing.active ? 'Active' : 'Inactive',
            },
      onSave: (values) async {
        try {
          final pkgLabel = values['default_package_type'];
          final pkgId = (pkgLabel == null || pkgLabel == _none)
              ? null
              : packageTypes
                  .where((e) => e.label == pkgLabel)
                  .firstOrNull
                  ?.id;
          final nature = (values['nature_of_goods'] ?? '').trim();
          final active = values['active'] != 'Inactive';

          final n = ref.read(partDescriptionsProvider.notifier);
          if (existing == null) {
            await n.add(PartDescription(
              name: values['name'] ?? '',
              natureOfGoods: nature.isEmpty ? null : nature,
              defaultPackageTypeId: pkgId,
              active: active,
            ));
          } else {
            await n.update(PartDescription(
              id: existing.id,
              version: existing.version,
              name: values['name'] ?? existing.name,
              natureOfGoods: nature.isEmpty ? null : nature,
              defaultPackageTypeId: pkgId,
              active: active,
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
    final parts = ref.watch(partDescriptionsProvider);
    final packageTypes =
        lookupList(ref.watch(lookupsMapProvider), 'PACKAGE_TYPE');
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManagePartDescriptions ?? false;

    return MasterPage(
      title: 'Part Descriptions',
      subtitle: '${parts.length} entries · auto-fill enabled',
      icon: Icons.inventory_2_outlined,
      canEdit: canEdit,
      onAdd: canEdit
          ? () => _openForm(context, ref, packageTypes: packageTypes)
          : null,
      onEdit: canEdit
          ? (id) {
              final p = parts.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: p, packageTypes: packageTypes);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this part description');
              if (!ok) return;
              try {
                await ref.read(partDescriptionsProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const [
        'Name',
        'Nature of Goods',
        'Default Package',
        'Active',
      ],
      rows: [
        for (final p in parts)
          MasterRow(
            id: p.id ?? '',
            cells: [
              p.name,
              p.natureOfGoods ?? '—',
              p.defaultPackageTypeLabel ?? '—',
              p.active ? 'Active' : 'Inactive',
            ],
          ),
      ],
    );
  }
}
