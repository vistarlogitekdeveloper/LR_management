import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/mock_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';

class LrListScreen extends ConsumerWidget {
  const LrListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(filteredLrsProvider);
    final filter = ref.watch(lrFilterProvider);

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
              padding: const EdgeInsets.all(28),
              child: AppCard(
                padding: const EdgeInsets.all(16),
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search LR, party, vehicle, EWB…',
              prefixIcon: Icon(Icons.search, color: AppColors.slate),
            ),
            onChanged: (v) => ref
                .read(lrFilterProvider.notifier)
                .update((s) => s.copyWith(query: v)),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<LrStatus?>(
            initialValue: filter.status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All status')),
              for (final s in LrStatus.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) => ref.read(lrFilterProvider.notifier).update(
                (s) => v == null
                    ? s.copyWith(clearStatus: true)
                    : s.copyWith(status: v)),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            initialValue: filter.route,
            decoration: const InputDecoration(labelText: 'Route'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All routes')),
              for (final r in MockData.routes)
                DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (v) => ref.read(lrFilterProvider.notifier).update(
                (s) => v == null
                    ? s.copyWith(clearRoute: true)
                    : s.copyWith(route: v)),
          ),
        ),
      ],
    );
  }
}

class _LrTable extends StatelessWidget {
  final List<LorryReceipt> lrs;
  const _LrTable({required this.lrs});

  @override
  Widget build(BuildContext context) {
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          AppColors.plum.withValues(alpha: 0.05),
        ),
        columnSpacing: 24,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 56,
        columns: const [
          DataColumn(label: Text('LR Number')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Consignor')),
          DataColumn(label: Text('Consignee')),
          DataColumn(label: Text('Vehicle')),
          DataColumn(label: Text('Route')),
          DataColumn(label: Text('Freight')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Pay')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final lr in lrs)
            DataRow(
              cells: [
                DataCell(Text(lr.number,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(formatDate(lr.date))),
                DataCell(Text(lr.consignor.name,
                    overflow: TextOverflow.ellipsis)),
                DataCell(Text(lr.consignee.name,
                    overflow: TextOverflow.ellipsis)),
                DataCell(Text(lr.vehicle.number)),
                DataCell(Text(lr.route)),
                DataCell(Text(inr(lr.freight.total))),
                DataCell(StatusPill(status: lr.status)),
                DataCell(PayPill(pay: lr.payType)),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'View',
                      icon: const Icon(Icons.visibility_outlined,
                          color: AppColors.plum, size: 18),
                      onPressed: () => context.go('/lrs/${lr.id}'),
                    ),
                    IconButton(
                      tooltip: 'Print',
                      icon: const Icon(Icons.print_outlined,
                          color: AppColors.plum, size: 18),
                      onPressed: () => context.go('/lrs/${lr.id}/print'),
                    ),
                  ],
                )),
              ],
            ),
        ],
      ),
    );
  }
}
