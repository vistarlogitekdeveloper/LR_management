import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../masters/widgets/master_actions.dart';
import '../../masters/widgets/master_page.dart';
import '../providers/capacity_options_provider.dart';

/// Admin screen to manage the Vehicle Capacity dropdown options shown on the LR
/// form. Options are tenant-scoped — adding / renaming / removing here only
/// affects this tenant. "Remove" deactivates the option (existing LRs that used
/// it keep their value).
class CapacityOptionsScreen extends ConsumerWidget {
  const CapacityOptionsScreen({super.key});

  Future<String?> _promptLabel(BuildContext context, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial.isEmpty ? 'Add Capacity Option' : 'Rename Option'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'e.g. 25 Ton',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(capacityOptionsProvider);
    final n = ref.read(capacityOptionsProvider.notifier);

    return MasterPage(
      title: 'Vehicle Capacity Options',
      subtitle:
          '${options.length} options · shown in the LR "Vehicle Capacity" dropdown',
      icon: Icons.scale_outlined,
      canEdit: true,
      onAdd: () async {
        final label = await _promptLabel(context);
        if (label == null || label.isEmpty) return;
        try {
          await n.add(label);
        } catch (e) {
          if (context.mounted) MasterActions.showError(context, e);
        }
      },
      onEdit: (id) async {
        final current = options.firstWhere((o) => o.id == id);
        final label = await _promptLabel(context, initial: current.label);
        if (label == null || label.isEmpty || label == current.label) return;
        try {
          await n.rename(id, label);
        } catch (e) {
          if (context.mounted) MasterActions.showError(context, e);
        }
      },
      onDelete: (id) async {
        final ok = await MasterActions.confirmDelete(
          context: context,
          label: 'this capacity option',
        );
        if (!ok) return;
        try {
          await n.remove(id);
        } catch (e) {
          if (context.mounted) MasterActions.showError(context, e);
        }
      },
      columns: const ['Option', 'Code'],
      rows: [
        for (final o in options) MasterRow(id: o.id, cells: [o.label, o.code]),
      ],
    );
  }
}
