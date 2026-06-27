import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';
import '../widgets/party_form_dialog.dart';

class PartiesScreen extends ConsumerWidget {
  const PartiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partiesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageParties ?? false;

    return MasterPage(
      title: 'Parties',
      subtitle: '${parties.length} parties · consignor / consignee / customer',
      icon: Icons.business_outlined,
      canEdit: canEdit,
      onAdd: canEdit
          ? () => PartyFormDialog.show(context)
          : null,
      onEdit: canEdit
          ? (id) {
              final p = parties.firstWhere((x) => x.id == id);
              PartyFormDialog.show(context, existing: p);
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
      columns: const ['Name', 'Roles', 'GST', 'City', 'Contact', 'Mobile'],
      rows: [
        for (final p in parties)
          MasterRow(
            id: p.id,
            cells: [p.name, p.roleLabel, p.gst, p.city, p.contact, p.mobile],
          ),
      ],
    );
  }
}
