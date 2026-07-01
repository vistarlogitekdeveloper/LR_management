import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/route_master.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/master_providers.dart';
import '../widgets/master_actions.dart';
import '../widgets/master_page.dart';
import '../widgets/route_form_dialog.dart';

class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canManageRoutes ?? false;
    // Operators don't see the customer rate (margin); admins/super admins do.
    final showCustomerRate = user?.canViewCustomerRate ?? false;

    Future<void> openForm({RouteMaster? existing}) =>
        RouteFormDialog.show(context, existing: existing);

    return MasterPage(
      title: 'Routes',
      subtitle: '${routes.length} routes with rate mapping',
      icon: Icons.route_outlined,
      canEdit: canEdit,
      onAdd: canEdit ? () => openForm() : null,
      onEdit: canEdit
          ? (id) {
              final r = routes.firstWhere((x) => x.id == id);
              openForm(existing: r);
            }
          : null,
      onDelete: canEdit
          ? (id) async {
              final ok = await MasterActions.confirmDelete(
                context: context,
                label: 'this route',
              );
              if (!ok) return;
              try {
                await ref.read(routesProvider.notifier).remove(id);
              } catch (e) {
                if (context.mounted) MasterActions.showError(context, e);
              }
            }
          : null,
      columns: [
        'From',
        'To',
        'Distance (km)',
        'Transporter Rate (₹)',
        if (showCustomerRate) 'Customer Rate',
      ],
      rows: [
        for (final r in routes)
          MasterRow(
            id: r.id,
            cells: [
              r.hasFromCoords ? '📍 ${r.fromCity}' : r.fromCity,
              r.hasToCoords ? '📍 ${r.toCity}' : r.toCity,
              r.distanceKm.toStringAsFixed(0),
              inr(r.baseRate),
              if (showCustomerRate)
                r.customerRate > 0 ? inr(r.customerRate) : '—',
            ],
          ),
      ],
    );
  }
}
