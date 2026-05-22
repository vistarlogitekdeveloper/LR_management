import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../lr/providers/lr_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../services/export_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lrs = ref.watch(lrListProvider);

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Reports',
            subtitle: 'Daily · Monthly · Accounts',
            actions: [
              AppButton(
                label: 'Export CSV',
                icon: Icons.file_download_outlined,
                kind: BtnKind.soft,
                onPressed: () async {
                  await ExportService.exportLrsCsv(lrs);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('LRs exported as CSV')),
                  );
                },
              ),
            ],
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.plum,
              unselectedLabelColor: AppColors.slate,
              indicatorColor: AppColors.plum,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              tabs: const [
                Tab(text: 'Daily'),
                Tab(text: 'Monthly'),
                Tab(text: 'Accounts'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _DailyTab(lrs: lrs),
                _MonthlyTab(lrs: lrs),
                _AccountsTab(lrs: lrs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyTab extends StatelessWidget {
  final List<LorryReceipt> lrs;
  const _DailyTab({required this.lrs});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todays = lrs
        .where((lr) =>
            lr.date.year == today.year &&
            lr.date.month == today.month &&
            lr.date.day == today.day)
        .toList();
    final routeWise = <String, int>{};
    final vehicleWise = <String, int>{};
    for (final lr in lrs) {
      routeWise[lr.route] = (routeWise[lr.route] ?? 0) + 1;
      vehicleWise[lr.vehicle.number] =
          (vehicleWise[lr.vehicle.number] ?? 0) + 1;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(items: [
            ('LRs Today', '${todays.length}'),
            ('Total LRs', '${lrs.length}'),
            ('In Transit',
                '${lrs.where((l) => l.status == LrStatus.inTransit).length}'),
          ]),
          const SizedBox(height: 20),
          _BreakdownCard(
            title: 'Route-wise dispatch',
            icon: Icons.alt_route_rounded,
            items: routeWise.entries
                .map((e) => (e.key, '${e.value}'))
                .toList(),
          ),
          const SizedBox(height: 16),
          _BreakdownCard(
            title: 'Vehicle-wise dispatch',
            icon: Icons.local_shipping_outlined,
            items: vehicleWise.entries
                .map((e) => (e.key, '${e.value}'))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTab extends StatelessWidget {
  final List<LorryReceipt> lrs;
  const _MonthlyTab({required this.lrs});

  @override
  Widget build(BuildContext context) {
    final customerCount = <String, int>{};
    final customerFreight = <String, double>{};
    final vehicleUtilization = <String, int>{};
    for (final lr in lrs) {
      customerCount[lr.consignor.name] =
          (customerCount[lr.consignor.name] ?? 0) + 1;
      customerFreight[lr.consignor.name] =
          (customerFreight[lr.consignor.name] ?? 0) + lr.freight.total;
      vehicleUtilization[lr.vehicle.number] =
          (vehicleUtilization[lr.vehicle.number] ?? 0) + 1;
    }
    final totalFreight =
        lrs.fold<double>(0, (s, l) => s + l.freight.total);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(items: [
            ('Total Freight', inr(totalFreight)),
            ('Customers Active', '${customerCount.length}'),
            ('Vehicles Used', '${vehicleUtilization.length}'),
          ]),
          const SizedBox(height: 20),
          _BreakdownCard(
            title: 'Customer-wise LR count',
            icon: Icons.people_outline,
            items: customerCount.entries
                .map((e) => (e.key, '${e.value}'))
                .toList(),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Customer freight summary',
                ),
                for (final entry in customerFreight.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          inr(entry.value),
                          style: const TextStyle(
                            color: AppColors.plum,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _BreakdownCard(
            title: 'Vehicle utilization',
            icon: Icons.local_shipping_outlined,
            items: vehicleUtilization.entries
                .map((e) => (e.key, '${e.value} trips'))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _AccountsTab extends ConsumerWidget {
  final List<LorryReceipt> lrs;
  const _AccountsTab({required this.lrs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAdvance =
        lrs.fold<double>(0, (s, l) => s + l.freight.advance);
    final totalPending = lrs
        .where((l) => l.freight.balance > 0)
        .fold<double>(0, (s, l) => s + l.freight.balance);
    final margin =
        lrs.fold<double>(0, (s, l) => s + l.freight.vistarMargin);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(items: [
            ('Advance Received', inr(totalAdvance)),
            ('Pending Freight', inr(totalPending)),
            ('Margin (MTD)', inr(margin)),
          ]),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  icon: Icons.book_outlined,
                  title: 'Customer ledger',
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Export per-customer freight ledger for accounting.',
                        style: const TextStyle(
                            color: AppColors.slate, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppButton(
                      label: 'Tally export',
                      icon: Icons.file_download_outlined,
                      kind: BtnKind.soft,
                      small: true,
                      onPressed: () async {
                        await ExportService.exportTally(lrs);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Tally-format file generated')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final List<(String, String)> items;
  const _StatRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 700 ? items.length : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final s in items)
              SizedBox(
                width: (c.maxWidth - 16 * (cols - 1)) / cols,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.$1,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.$2,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> items;

  const _BreakdownCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(icon: icon, title: title),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.$1,
                      style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.plum.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.$2,
                      style: const TextStyle(
                        color: AppColors.plum,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
