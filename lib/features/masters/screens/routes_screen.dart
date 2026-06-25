import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/route_master.dart';
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
            label: 'From Location / City',
            required: true,
            hint: 'Short company name - location · e.g. VLL - Pune',
            initialValue: r?.fromCity),
        FormFieldSpec(
            name: 'toCity',
            label: 'To Location / City',
            required: true,
            hint: 'Short company name - location · e.g. TATA - Chakan',
            initialValue: r?.toCity),
        FormFieldSpec(
            name: 'distanceKm',
            label: 'Distance (km)',
            type: FieldType.number,
            required: true,
            initialValue: r?.distanceKm.toStringAsFixed(0)),
        FormFieldSpec(
            name: 'baseRate',
            label: 'Transporter Rate (₹)',
            type: FieldType.number,
            required: true,
            hint: 'Standard/transporter cost',
            initialValue: r?.baseRate.toStringAsFixed(0)),
        FormFieldSpec(
            name: 'customerRate',
            label: 'Customer Rate (₹)',
            type: FieldType.number,
            hint: 'Rate charged to customer · used for Vistar margin',
            initialValue:
                (r != null && r.customerRate > 0) ? r.customerRate.toStringAsFixed(0) : ''),
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
              'customerRate': existing.customerRate > 0
                  ? existing.customerRate.toStringAsFixed(0)
                  : '',
            },
      onSave: (values) async {
        try {
          final n = ref.read(routesProvider.notifier);
          final distance = double.tryParse(values['distanceKm'] ?? '0') ?? 0;
          final rate = double.tryParse(values['baseRate'] ?? '0') ?? 0;
          final customerRate =
              double.tryParse(values['customerRate'] ?? '0') ?? 0;
          if (existing == null) {
            await n.add(RouteMaster(
              id: const Uuid().v4(),
              fromCity: values['fromCity'] ?? '',
              toCity: values['toCity'] ?? '',
              distanceKm: distance,
              baseRate: rate,
              customerRate: customerRate,
            ));
          } else {
            await n.update(existing.copyWith(
              fromCity: values['fromCity'],
              toCity: values['toCity'],
              distanceKm: distance,
              baseRate: rate,
              customerRate: customerRate,
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
    final routes = ref.watch(routesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageRoutes ?? false;

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
              if (!ok) return;
              try {
                await ref.read(routesProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const [
        'From',
        'To',
        'Distance (km)',
        'Transporter Rate (₹)',
        'Customer Rate',
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
              r.customerRate > 0 ? inr(r.customerRate) : '—',
            ],
          ),
      ],
    );
  }
}
