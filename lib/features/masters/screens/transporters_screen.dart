import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/transporter.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';
import '../widgets/transporter_form_dialog.dart';

class TransportersScreen extends ConsumerWidget {
  const TransportersScreen({super.key});

  Future<void> _openForm(BuildContext context, {Transporter? existing}) async {
    await TransporterFormDialog.show(context, existing: existing);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transporters = ref.watch(transportersProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageTransporters ?? false;

    return MasterPage(
      title: 'Transporter Master',
      subtitle: '${transporters.length} transporter partners',
      icon: Icons.alt_route_rounded,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context) : null,
      onEdit: canEdit
          ? (id) {
              final t = transporters.firstWhere((x) => x.id == id);
              _openForm(context, existing: t);
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
      columns: const ['Name', 'PAN', 'TDS Applicable', 'Bank', 'Cheque'],
      rows: [
        for (final t in transporters)
          MasterRow(id: t.id, cells: [
            t.name,
            t.pan,
            t.tds,
            t.bankName.isEmpty ? '—' : t.bankName,
            t.hasDocument ? 'On file' : '—',
          ]),
      ],
    );
  }
}
