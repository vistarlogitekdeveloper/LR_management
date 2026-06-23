import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/mock_data.dart';
import '../../../shared/models/driver.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lookups/data/lookup_value.dart';
import '../../lookups/providers/lookups_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

const _none = '(None)';

class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  static List<FormFieldSpec> _fields(
    Vehicle? v, {
    required List<String> vehicleTypes,
    required List<String> driverNames,
    required List<String> transporterNames,
  }) =>
      [
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
            options: vehicleTypes,
            initialValue: v?.type),
        FormFieldSpec(
            name: 'capacity',
            label: 'Capacity (MT)',
            type: FieldType.number,
            initialValue:
                (v != null && v.capacityMt > 0) ? v.capacityMt.toString() : ''),
        FormFieldSpec(
            name: 'driver',
            label: 'Assigned Driver',
            type: FieldType.dropdown,
            options: [_none, ...driverNames],
            initialValue: (v != null && v.driver.isNotEmpty) ? v.driver : _none),
        FormFieldSpec(
            name: 'transporter',
            label: 'Transporter',
            type: FieldType.dropdown,
            options: [_none, ...transporterNames],
            initialValue: (v != null && v.transporterName.isNotEmpty)
                ? v.transporterName
                : _none),
      ];

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Vehicle? existing,
    required List<LookupValue> vehicleTypes,
    required List<Driver> drivers,
    required List<Transporter> transporters,
  }) async {
    final typeLabels = vehicleTypes.isEmpty
        ? MockData.vehicleTypes
        : vehicleTypes.map((e) => e.label).toList();
    final driverNames = drivers.map((d) => d.name).toList();
    final transporterNames = transporters.map((t) => t.name).toList();

    await MasterFormDialog.show(
      context: context,
      title: existing == null ? 'New Vehicle' : 'Edit Vehicle',
      subtitle: 'Fleet master',
      fields: _fields(existing,
          vehicleTypes: typeLabels,
          driverNames: driverNames,
          transporterNames: transporterNames),
      initial: existing == null
          ? const {}
          : {
              'number': existing.number,
              'type': existing.type,
              'capacity':
                  existing.capacityMt > 0 ? existing.capacityMt.toString() : '',
              'driver': existing.driver.isEmpty ? _none : existing.driver,
              'transporter': existing.transporterName.isEmpty
                  ? _none
                  : existing.transporterName,
            },
      onSave: (values) async {
        try {
          final typeLabel = values['type'] ?? '';
          final typeId = vehicleTypes
              .where((e) => e.label == typeLabel)
              .map((e) => e.id)
              .cast<String?>()
              .firstWhere((_) => true, orElse: () => null);
          final driverName = values['driver'];
          final driver = (driverName == null || driverName == _none)
              ? null
              : drivers.where((d) => d.name == driverName).cast<Driver?>().firstWhere(
                  (_) => true,
                  orElse: () => null);
          final trName = values['transporter'];
          final transporter = (trName == null || trName == _none)
              ? null
              : transporters
                  .where((t) => t.name == trName)
                  .cast<Transporter?>()
                  .firstWhere((_) => true, orElse: () => null);
          final capacity = double.tryParse(values['capacity'] ?? '') ?? 0;

          final n = ref.read(vehiclesProvider.notifier);
          if (existing == null) {
            await n.add(Vehicle(
              id: const Uuid().v4(),
              number: values['number'] ?? '',
              typeId: typeId ?? '',
              type: typeLabel,
              capacityMt: capacity,
              transporterId: transporter?.id,
              transporterName: transporter?.name ?? '',
              currentDriverId: driver?.id,
              driver: driver?.name ?? '',
              driverMobile: driver?.mobile ?? '',
            ));
          } else {
            await n.update(existing.copyWith(
              number: values['number'],
              typeId: typeId ?? existing.typeId,
              type: typeLabel,
              capacityMt: capacity,
              transporterId: transporter?.id,
              transporterName: transporter?.name ?? '',
              currentDriverId: driver?.id,
              driver: driver?.name ?? '',
              driverMobile: driver?.mobile ?? '',
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
    final vehicles = ref.watch(vehiclesProvider);
    final drivers = ref.watch(driversProvider);
    final transporters = ref.watch(transportersProvider);
    final vehicleTypes =
        lookupList(ref.watch(lookupsMapProvider), 'VEHICLE_TYPE');
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role == UserRole.admin;

    return MasterPage(
      title: 'Vehicles & Drivers',
      subtitle: '${vehicles.length} vehicles in fleet',
      icon: Icons.local_shipping_outlined,
      canEdit: canEdit,
      onAdd: canEdit
          ? () => _openForm(context, ref,
              vehicleTypes: vehicleTypes,
              drivers: drivers,
              transporters: transporters)
          : null,
      onEdit: canEdit
          ? (id) {
              final v = vehicles.firstWhere((x) => x.id == id);
              _openForm(context, ref,
                  existing: v,
                  vehicleTypes: vehicleTypes,
                  drivers: drivers,
                  transporters: transporters);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                  context: context, label: 'this vehicle');
              if (!ok) return;
              try {
                await ref.read(vehiclesProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: const [
        'Vehicle No',
        'Type',
        'Capacity',
        'Driver',
        'Driver Mobile',
        'Transporter',
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
              v.transporterName,
            ],
          ),
      ],
    );
  }
}
