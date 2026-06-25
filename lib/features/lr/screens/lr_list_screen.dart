import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../masters/providers/master_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';

class LrListScreen extends ConsumerWidget {
  const LrListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(filteredLrsProvider);
    final filter = ref.watch(lrFilterProvider);
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
                    _LrTable(lrs: lrs),
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
          ],
        );
      },
    );
  }
}

class _LrTable extends StatefulWidget {
  final List<LorryReceipt> lrs;
  const _LrTable({required this.lrs});

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
            children: [for (final lr in lrs) _LrMobileCard(lr: lr)],
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
              columns: const [
                DataColumn(label: Text('')),
                DataColumn(label: Text('LR Number')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Consignor')),
                DataColumn(label: Text('Consignee')),
                DataColumn(label: Text('Vehicle')),
                DataColumn(label: Text('Route')),
                DataColumn(label: Text('Freight')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Pay')),
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
  const _LrMobileCard({required this.lr});

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
                  inr(lr.freight.total),
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
