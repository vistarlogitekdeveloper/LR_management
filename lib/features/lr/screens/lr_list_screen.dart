import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../auth/providers/auth_provider.dart';
import '../../masters/providers/master_providers.dart';
import '../../masters/widgets/master_actions.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';

/// Confirm + delete an LR from the list. Calls the same notifier.remove ->
/// DELETE /lrs/:id used by the detail screen; the list refreshes from state.
Future<void> _confirmDeleteLr(
  BuildContext context,
  WidgetRef ref,
  LorryReceipt lr,
) async {
  final ok = await showConfirmDialog(
    context: context,
    title: 'Delete LR ${lr.number}?',
    message:
        'This cannot be undone. The LR record will be removed from the system.',
    confirmLabel: 'Delete LR',
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(lrListProvider.notifier).remove(lr.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LR ${lr.number} deleted')),
      );
    }
  } catch (e) {
    if (context.mounted) MasterActions.showError(context, e);
  }
}

/// Confirm + send an LR to Accounts for payment. Reuses the same
/// notifier.sendForPayment -> POST /lrs/:id/send-for-payment used by the detail
/// screen; the row updates from state (the action then hides itself).
Future<void> _confirmSendForPayment(
  BuildContext context,
  WidgetRef ref,
  LorryReceipt lr,
) async {
  final ok = await showConfirmDialog(
    context: context,
    title: 'Send LR ${lr.number} for payment?',
    message:
        'This notifies the Accounts team by email and adds this LR to their '
        'payment queue. This can only be done once.',
    confirmLabel: 'Send for payment',
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(lrListProvider.notifier).sendForPayment(lr.id, lr.version);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LR ${lr.number} sent to Accounts for payment')),
      );
    }
  } catch (e) {
    if (context.mounted) MasterActions.showError(context, e);
  }
}

class LrListScreen extends ConsumerWidget {
  const LrListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(filteredLrsProvider);
    final filter = ref.watch(lrFilterProvider);
    final user = ref.watch(currentUserProvider);
    final canDelete = user?.canDeleteLr ?? false;
    // Transporter-side amount (the Freight column) hides without the perm.
    final canViewTransporterRate = user?.canViewTransporterRate ?? false;
    // The ops user who creates/manages LRs is the one who sends it to Accounts.
    final canSend = (user?.canCreateLr ?? false) ||
        (user?.canEditLr ?? false) ||
        (user?.canAdmin ?? false);
    final mobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Lorry Receipts',
            subtitle: '${lrs.length} records',
            actions: [
              AppButton(
                label: 'Create LR',
                icon: Icons.add_rounded,
                onPressed: () => context.go('/lrs/new'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(mobile ? 14 : 28),
              child: AppCard(
                padding: EdgeInsets.all(mobile ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilterBar(filter: filter),
                    const SizedBox(height: 14),
                    _LrTable(
                      lrs: lrs,
                      canViewTransporterRate: canViewTransporterRate,
                      onDelete: canDelete
                          ? (lr) => _confirmDeleteLr(context, ref, lr)
                          : null,
                      onSendForPayment: canSend
                          ? (lr) => _confirmSendForPayment(context, ref, lr)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final LrFilter filter;
  const _FilterBar({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final mobile = c.maxWidth < 600;
        final fieldStyle = TextStyle(
          fontSize: mobile ? 13 : 14,
          color: AppColors.ink,
        );

        final search = TextField(
          style: fieldStyle,
          decoration: InputDecoration(
            isDense: mobile,
            hintText: mobile ? 'Search…' : 'Search LR, party, vehicle, EWB…',
            prefixIcon: const Icon(Icons.search, color: AppColors.slate),
          ),
          onChanged: (v) => ref
              .read(lrFilterProvider.notifier)
              .update((s) => s.copyWith(query: v)),
        );

        final status = SearchableField<LrStatus>(
          value: filter.status,
          options: LrStatus.values,
          labelOf: (s) => s.label,
          hintText: 'All status',
          dialogTitle: 'Select status',
          clearable: true,
          onChanged: (v) => ref
              .read(lrFilterProvider.notifier)
              .update(
                (s) => v == null
                    ? s.copyWith(clearStatus: true)
                    : s.copyWith(status: v),
              ),
        );

        final route = SearchableField<String>(
          value: filter.route,
          options: ref.watch(routesProvider).map((r) => r.name).toList(),
          labelOf: (r) => r,
          hintText: 'All routes',
          dialogTitle: 'Select route',
          clearable: true,
          onChanged: (v) => ref
              .read(lrFilterProvider.notifier)
              .update(
                (s) => v == null
                    ? s.copyWith(clearRoute: true)
                    : s.copyWith(route: v),
              ),
        );

        // Region options derived from the loaded LRs: region_id -> short code
        // embedded in the LR number ({prefix}/{REGION}/{FY}/{seq}). Same source
        // as the MIS region filter — no backend field needed. Shown whenever
        // at least one region is present in the loaded LRs.
        final regionCodes = <String, String>{};
        for (final lr in ref.watch(lrListProvider)) {
          final rid = lr.regionId;
          if (rid == null || rid.isEmpty) continue;
          final parts = lr.number.split('/');
          if (parts.length > 1 &&
              RegExp(r'^[A-Za-z]{2,6}$').hasMatch(parts[1])) {
            regionCodes[rid] = parts[1].toUpperCase();
          }
        }
        final regionIds = regionCodes.keys.toList()
          ..sort((a, b) => regionCodes[a]!.compareTo(regionCodes[b]!));
        final hasRegions = regionIds.isNotEmpty;
        final region = SearchableField<String>(
          value: filter.region,
          options: regionIds,
          labelOf: (id) => regionCodes[id] ?? id,
          hintText: 'All regions',
          dialogTitle: 'Select region',
          clearable: true,
          onChanged: (v) => ref.read(lrFilterProvider.notifier).update(
                (s) => v == null
                    ? s.copyWith(clearRegion: true)
                    : s.copyWith(region: v),
              ),
        );

        if (mobile) {
          // All three filters in a single row — no wasted blank space, no
          // horizontal scroll. Flexible widths share the available space.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: search),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: status),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: route),
              if (hasRegions) ...[
                const SizedBox(width: 8),
                Expanded(flex: 4, child: region),
              ],
            ],
          );
        }

        // Wider screens: roomy fixed-width fields that wrap if needed.
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 280, child: search),
            SizedBox(width: 180, child: status),
            SizedBox(width: 220, child: route),
            if (hasRegions) SizedBox(width: 180, child: region),
          ],
        );
      },
    );
  }
}

class _LrTable extends StatefulWidget {
  final List<LorryReceipt> lrs;
  final bool canViewTransporterRate;
  final void Function(LorryReceipt lr)? onDelete;
  final void Function(LorryReceipt lr)? onSendForPayment;
  const _LrTable({
    required this.lrs,
    required this.canViewTransporterRate,
    this.onDelete,
    this.onSendForPayment,
  });

  @override
  State<_LrTable> createState() => _LrTableState();
}

class _LrTableState extends State<_LrTable> {
  final ScrollController _hController = ScrollController();

  @override
  void dispose() {
    _hController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lrs = widget.lrs;
    if (lrs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: const Text(
          'No LRs found',
          style: TextStyle(color: AppColors.slate),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Phones get stacked cards; wider screens get the scrollable table.
        if (c.maxWidth < 720) {
          return Column(
            children: [
              for (final lr in lrs)
                _LrMobileCard(
                  lr: lr,
                  canViewTransporterRate: widget.canViewTransporterRate,
                  onDelete: widget.onDelete == null
                      ? null
                      : () => widget.onDelete!(lr),
                  onSendForPayment: widget.onSendForPayment == null
                      ? null
                      : () => widget.onSendForPayment!(lr),
                ),
            ],
          );
        }
        return Scrollbar(
          controller: _hController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _hController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 12),
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                AppColors.plum.withValues(alpha: 0.05),
              ),
              columnSpacing: 24,
              dataRowMinHeight: 52,
              dataRowMaxHeight: 56,
              columns: [
                const DataColumn(label: Text('')),
                const DataColumn(label: Text('LR Number')),
                const DataColumn(label: Text('Date')),
                const DataColumn(label: Text('Consignor')),
                const DataColumn(label: Text('Consignee')),
                const DataColumn(label: Text('Vehicle')),
                const DataColumn(label: Text('Route')),
                if (widget.canViewTransporterRate)
                  const DataColumn(label: Text('Freight')),
                const DataColumn(label: Text('Status')),
                const DataColumn(label: Text('Pay')),
              ],
              rows: [
                for (final lr in lrs)
                  DataRow(
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View',
                              icon: const Icon(
                                Icons.visibility_outlined,
                                color: AppColors.plum,
                                size: 18,
                              ),
                              onPressed: () => context.go('/lrs/${lr.id}'),
                            ),
                            // Print is available as soon as the LR is saved.
                            IconButton(
                              tooltip: 'Print',
                              icon: const Icon(
                                Icons.print_outlined,
                                color: AppColors.plum,
                                size: 18,
                              ),
                              onPressed: () =>
                                  context.go('/lrs/${lr.id}/print'),
                            ),
                            if (widget.onSendForPayment != null &&
                                !lr.sentForPayment)
                              IconButton(
                                tooltip: 'Send for Payment',
                                icon: const Icon(
                                  Icons.forward_to_inbox_outlined,
                                  color: AppColors.ok,
                                  size: 18,
                                ),
                                onPressed: () => widget.onSendForPayment!(lr),
                              ),
                            // Sent-for-payment LRs are locked from deletion.
                            if (widget.onDelete != null && !lr.sentForPayment)
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                  size: 18,
                                ),
                                onPressed: () => widget.onDelete!(lr),
                              ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          lr.number,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(Text(formatDate(lr.date))),
                      DataCell(
                        Text(
                          lr.consignor.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        Text(
                          lr.consignee.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(Text(lr.vehicle.number)),
                      DataCell(Text(lr.route)),
                      if (widget.canViewTransporterRate)
                        DataCell(Text(inr(lr.freight.total))),
                      DataCell(StatusPill(status: lr.status)),
                      DataCell(PayPill(pay: lr.payType)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LrMobileCard extends StatelessWidget {
  final LorryReceipt lr;
  final bool canViewTransporterRate;
  final VoidCallback? onDelete;
  final VoidCallback? onSendForPayment;
  const _LrMobileCard({
    required this.lr,
    required this.canViewTransporterRate,
    this.onDelete,
    this.onSendForPayment,
  });

  @override
  Widget build(BuildContext context) {
    final cleared = lr.freight.total > 0 && lr.freight.balance <= 0;
    final meta = [
      formatDate(lr.date),
      if (lr.vehicle.number.isNotEmpty) lr.vehicle.number,
      if (lr.route.isNotEmpty) lr.route,
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/lrs/${lr.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    lr.number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'View',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.visibility_outlined,
                    color: AppColors.plum,
                    size: 18,
                  ),
                  onPressed: () => context.go('/lrs/${lr.id}'),
                ),
                // Print is available as soon as the LR is saved.
                IconButton(
                  tooltip: 'Print',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.print_outlined,
                    color: AppColors.plum,
                    size: 18,
                  ),
                  onPressed: () => context.go('/lrs/${lr.id}/print'),
                ),
                if (onSendForPayment != null && !lr.sentForPayment)
                  IconButton(
                    tooltip: 'Send for Payment',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.forward_to_inbox_outlined,
                      color: AppColors.ok,
                      size: 18,
                    ),
                    onPressed: onSendForPayment,
                  ),
                // Sent-for-payment LRs are locked from deletion.
                if (onDelete != null && !lr.sentForPayment)
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                      size: 18,
                    ),
                    onPressed: onDelete,
                  ),
              ],
            ),
            Text(
              '${lr.consignor.name} → ${lr.consignee.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(status: lr.status),
                PayPill(pay: lr.payType),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  canViewTransporterRate ? inr(lr.freight.total) : '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cleared ? AppColors.ok : AppColors.ink,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
