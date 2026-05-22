import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/mock_data.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  static List<FormFieldSpec> _fields(Vehicle? v) => [
        FormFieldSpec(
            name: 'number',
            label: 'Vehicle Number',
            required: true,
            initialValue: v?.number),
        FormFieldSpec(
            name: 'type',
            label: 'Vehicle Type',
            type: FieldType.dropdown,
            required: true,
            options: MockData.vehicleTypes,
            initialValue: v?.type),
        FormFieldSpec(
            name: 'capacity',
            label: 'Capacity (e.g. 10MT 22FT)',
            initialValue: v?.capacity),
        FormFieldSpec(
            name: 'driver', label: 'Driver Name', initialValue: v?.driver),
        FormFieldSpec(
            name: 'driverMobile',
            label: 'Driver Mobile',
            type: FieldType.number,
            maxLength: 12,
            initialValue: v?.driverMobile),
        FormFieldSpec(
            name: 'mode',
            label: 'Transport Mode',
            type: FieldType.dropdown,
            options: const ['Road', 'Rail', 'Air'],
            initialValue: v?.mode ?? 'Road'),
        FormFieldSpec(name: 'pmark', label: 'P-Mark', initialValue: v?.pmark),
      ];

  Future<void> _openForm(BuildContext context, WidgetRef ref,
      {Vehicle? existing}) async {
    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Vehicle' : 'Edit Vehicle',
      subtitle: 'Fleet master',
      fields: _fields(existing),
      initial: existing == null
          ? const {}
          : {
              'number': existing.number,
              'type': existing.type,
              'capacity': existing.capacity,
              'driver': existing.driver,
              'driverMobile': existing.driverMobile,
              'mode': existing.mode,
              'pmark': existing.pmark,
            },
      onSave: (values) async {
        final n = ref.read(vehiclesProvider.notifier);
        if (existing == null) {
          n.add(Vehicle(
            id: const Uuid().v4(),
            number: values['number'] ?? '',
            type: values['type'] ?? 'Truck',
            capacity: values['capacity'] ?? '',
            driver: values['driver'] ?? '',
            driverMobile: values['driverMobile'] ?? '',
            mode: values['mode'] ?? 'Road',
            pmark: values['pmark'] ?? '',
          ));
        } else {
          n.update(existing.copyWith(
            number: values['number'],
            type: values['type'],
            capacity: values['capacity'],
            driver: values['driver'],
            driverMobile: values['driverMobile'],
            mode: values['mode'],
            pmark: values['pmark'],
          ));
        }
        return true;
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehiclesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Vehicles & Drivers',
      subtitle: '${vehicles.length} vehicles in fleet',
      icon: Icons.local_shipping_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context, ref) : null,
      onEdit: canEdit
          ? (id) {
              final v = vehicles.firstWhere((x) => x.id == id);
              _openForm(context, ref, existing: v);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this vehicle');
              if (ok) ref.read(vehiclesProvider.notifier).remove(id);
            }
          : null,
      columns: const [
        'Vehicle No',
        'Type',
        'Capacity',
        'Driver',
        'Driver Mobile',
        'P-Mark',
      ],
      rows: [
        for (final v in vehicles)
          MasterRow(
            id: v.id,
            cells: [
              v.number,
              v.type,
              v.capacity,
              v.driver,
              v.driverMobile,
              v.pmark,
            ],
          ),
      ],
    );
  }
}
