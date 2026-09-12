import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/driver.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/driver_form_dialog.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';

class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  /// Both New Driver and Edit Driver. The bespoke dialog owns the save, the
  /// error snackbar and the list refresh — drivers carry file uploads now, and
  /// the generic MasterFormDialog cannot attach a file to a row it has just
  /// created. Same arrangement as the transporter master.
  Future<void> _openForm(BuildContext context, {Driver? existing}) async {
    await DriverFormDialog.show(context, existing: existing);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(driversProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageDrivers ?? false;

    return MasterPage(
      loading: ref.watch(driversLoadingProvider),
      title: 'Drivers',
      subtitle: '${drivers.length} drivers registered',
      icon: Icons.badge_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => _openForm(context) : null,
      onEdit: canEdit
          ? (id) {
              final d = drivers.firstWhere((x) => x.id == id);
              _openForm(context, existing: d);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                context: context,
                label: 'this driver',
              );
              if (!ok) return;
              try {
                await ref.read(driversProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      // MasterPage zips columns[i] to cells[i] positionally — keep the two
      // lists index-aligned. Address stays last because it is the widest.
      columns: const [
        'Name',
        'Mobile',
        'License No',
        'License Expiry',
        'Aadhaar',
        'PAN',
        'Address',
      ],
      rows: [
        for (final d in drivers)
          MasterRow(
            id: d.id,
            cells: [
              d.name,
              d.mobile,
              d.licenseNo,
              d.licenseExpiry ?? '—',
              _maskedAadhaar(d.aadhaar),
              d.pan.isEmpty ? '—' : d.pan,
              d.address,
            ],
          ),
      ],
    );
  }
}

/// Last four digits only. The full Aadhaar is on the form, where it was typed;
/// a master list sits open on a shared screen all day, and the last four are
/// enough to tell two drivers apart. '—' for every driver added before the KYC
/// fields existed — MasterPage's phone layout drops those rows from the card,
/// so an empty value costs no space there either.
String _maskedAadhaar(String aadhaar) {
  final digits = aadhaar.trim();
  if (digits.isEmpty) return '—';
  if (digits.length <= 4) return digits;
  return 'XXXX XXXX ${digits.substring(digits.length - 4)}';
}
