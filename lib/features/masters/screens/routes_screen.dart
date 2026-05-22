import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  static List<FormFieldSpec> _fields(RouteMaster? r) => [
        FormFieldSpec(
            name: 'fromCity',
            label: 'From City',
            required: true,
            initialValue: r?.fromCity),
        FormFieldSpec(
            name: 'toCity',
            label: 'To City',
            required: true,
            initialValue: r?.toCity),
        FormFieldSpec(
            name: 'distanceKm',
            label: 'Distance (km)',
            type: FieldType.number,
            required: true,
            initialValue: r?.distanceKm.toStringAsFixed(0)),
        FormFieldSpec(
            name: 'baseRate',
            label: 'Base Rate (₹)',
            type: FieldType.number,
            required: true,
            initialValue: r?.baseRate.toStringAsFixed(0)),
      ];

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {RouteMaster? existing}) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Route' : 'Edit Route',
      subtitle: 'Used for freight rate mapping',
      fields: _fields(existing),
      initial: existing == null
          ? const {}
          : {
              'fromCity': existing.fromCity,
              'toCity': existing.toCity,
              'distanceKm': existing.distanceKm.toStringAsFixed(0),
              'baseRate': existing.baseRate.toStringAsFixed(0),
            },
      onSave: (values) async {
        final n = ref.read(routesProvider.notifier);
        final distance = double.tryParse(values['distanceKm'] ?? '0') ?? 0;
        final rate = double.tryParse(values['baseRate'] ?? '0') ?? 0;
        if (existing == null) {
          n.add(RouteMaster(
            id: const Uuid().v4(),
            fromCity: values['fromCity'] ?? '',
            toCity: values['toCity'] ?? '',
            distanceKm: distance,
            baseRate: rate,
          ));
        } else {
          n.update(existing.copyWith(
            fromCity: values['fromCity'],
            toCity: values['toCity'],
            distanceKm: distance,
            baseRate: rate,
          ));
        }
        return true;
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Routes',
      subtitle: '${routes.length} routes with rate mapping',
      icon: Icons.route_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final r = routes.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: r);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this route');
              if (ok) ref.read(routesProvider.notifier).remove(id);
            }
          : null,
      columns: const [
        'From',
        'To',
        'Distance (km)',
        'Base Rate',
      ],
      rows: [
        for (final r in routes)
          MasterRow(
            id: r.id,
            cells: [
              r.fromCity,
              r.toCity,
              r.distanceKm.toStringAsFixed(0),
              inr(r.baseRate),
            ],
          ),
      ],
    );
  }
}
