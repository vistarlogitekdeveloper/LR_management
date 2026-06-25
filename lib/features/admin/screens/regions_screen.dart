import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../masters/widgets/master_page.dart';
import '../data/admin_repository.dart';
import '../providers/users_provider.dart';

class RegionsScreen extends ConsumerWidget {
  const RegionsScreen({super.key});

  static String _errorMessage(Object e) {
    if (e is DioException && e.error is ApiException) {
      return (e.error as ApiException).message;
    }
    if (e is ApiException) return e.message;
    return e.toString();
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {RegionInfo? existing}) async {
    final messenger = ScaffoldMessenger.of(context);
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Region' : 'Edit Region',
      subtitle: 'Operating area (e.g. Pune, Mumbai)',
      fields: [
        FormFieldSpec(
            name: 'name',
            label: 'Region Name',
            required: true,
            initialValue: existing?.name),
        FormFieldSpec(
            name: 'code',
            label: 'Short Code (optional)',
            initialValue: existing?.code),
      ],
      initial: existing == null
          ? const {}
          : {'name': existing.name, 'code': existing.code},
      onSave: (values) async {
        final n = ref.read(regionsProvider.notifier);
        final name = (values['name'] ?? '').trim();
        final code = (values['code'] ?? '').trim();
        try {
          if (existing == null) {
            await n.add(name: name, code: code.isEmpty ? null : code);
          } else {
            await n.update(existing, name: name, code: code);
          }
          return true;
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(_errorMessage(e))));
          return false;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regions = ref.watch(regionsProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageRegions ?? false;

    return MasterPage(
      title: 'Regions',
      subtitle: '${regions.length} operating regions',
      icon: Icons.public_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final r = regions.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: r);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await showConfirmDialog(
                context: context,
                title: 'Delete this region?',
                message:
                    'Regions with users assigned cannot be deleted — reassign them first.',
              );
              if (!ok) return;
              try {
                await ref.read(regionsProvider.notifier).remove(id);
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(_errorMessage(e))));
              }
            }
          : null,
      columns: const ['Region', 'Code', 'Status'],
      rows: [
        for (final r in regions)
          MasterRow(
            id: r.id,
            cells: [
              r.name,
              r.code.isEmpty ? '—' : r.code,
              r.active ? 'Active' : 'Inactive',
            ],
          ),
      ],
    );
  }
}
