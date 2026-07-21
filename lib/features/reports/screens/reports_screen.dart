import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lr/providers/lr_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/reports_providers.dart';
import '../services/export_service.dart';

// Optional date-range for the MIS download. The backend applies ?from&to
// (verified); region / user-wise filtering still needs backend support.
final _misRangeProvider = StateProvider<DateTimeRange?>((ref) => null);
// MIS region_id / created_by filters. Options are derived from the
// accounts-visible LRs (the /admin regions & users endpoints are 403 for the
// accounts role).
final _misRegionProvider = StateProvider<String?>((ref) => null);
final _misCreatorProvider = StateProvider<String?>((ref) => null);
// MIS payment-stage filter (Accounts' "sent for advance"): null = all LRs,
// true = only those sent for payment, false = only those not yet sent.
final _misSentProvider = StateProvider<bool?>((ref) => null);

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  // The all-financial "Accounts" tab is dropped for users without amount access
  // (operators) — 2 tabs instead of 3. This is the pre-existing coarse role gate
  // (canViewAmounts); the per-field visibility perms below are separate.
  late final bool _canAmounts;
  // Per-field visibility (migration 072) — purely permission-driven: migration
  // grants these perms to every role, so an operator who holds them sees the
  // amounts too, and a super admin revokes per user to hide. Independent of
  // _canAmounts, which only decides whether the all-financial Accounts tab
  // exists (that stays role-gated via canViewAmounts).
  late final bool _showFreight; // transporter-side amounts (freight/total/…)
  late final bool _showMargin; // Vistar margin

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _canAmounts = user?.canViewAmounts ?? false;
    _showFreight = user?.canViewTransporterRate ?? false;
    _showMargin = user?.canViewVistarMargin ?? false;
    _tab = TabController(length: _canAmounts ? 3 : 2, vsync: this);
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
            subtitle: _canAmounts ? 'Daily · Monthly · Accounts' : 'Daily · Monthly',
            actions: [
              AppButton(
                label: 'Download Excel',
                icon: Icons.file_download_outlined,
                kind: BtnKind.soft,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ExportService.exportLrsExcel(
                    lrs,
                    canViewTransporterRate: _showFreight,
                    canViewVistarMargin: _showMargin,
                  );
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('LRs exported as Excel')),
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
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
              tabs: [
                const Tab(text: 'Daily'),
                const Tab(text: 'Monthly'),
                if (_canAmounts) const Tab(text: 'Accounts'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _DailyTab(lrs: lrs),
                _MonthlyTab(lrs: lrs, showFreight: _showFreight),
                if (_canAmounts) _AccountsTab(lrs: lrs),
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
        .where(
          (lr) =>
              lr.date.year == today.year &&
              lr.date.month == today.month &&
              lr.date.day == today.day,
        )
        .toList();
    final routeWise = <String, int>{};
    final vehicleWise = <String, int>{};
    for (final lr in lrs) {
      routeWise[lr.route] = (routeWise[lr.route] ?? 0) + 1;
      vehicleWise[lr.vehicle.number] =
          (vehicleWise[lr.vehicle.number] ?? 0) + 1;
    }
    final mobile = MediaQuery.of(context).size.width < 600;
    final pad = mobile ? 14.0 : 28.0;
    final gap = mobile ? 10.0 : 20.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(
            items: [
              ('LRs Today', '${todays.length}'),
              ('Total LRs', '${lrs.length}'),
              (
                'In Transit',
                '${lrs.where((l) => l.status == LrStatus.inTransit).length}',
              ),
            ],
          ),
          SizedBox(height: gap),
          _BreakdownCard(
            title: 'Route-wise dispatch',
            icon: Icons.alt_route_rounded,
            items: routeWise.entries.map((e) => (e.key, '${e.value}')).toList(),
          ),
          SizedBox(height: mobile ? 10 : 16),
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
  // Already AND-ed with canViewAmounts by the parent — true only when the user
  // may see amounts AND holds VIEW_TRANSPORTER_RATE.
  final bool showFreight;
  const _MonthlyTab({required this.lrs, required this.showFreight});

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
    final totalFreight = lrs.fold<double>(0, (s, l) => s + l.freight.total);
    final mobile = MediaQuery.of(context).size.width < 600;
    final pad = mobile ? 14.0 : 28.0;
    final gap = mobile ? 10.0 : 20.0;
    final gap2 = mobile ? 10.0 : 16.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(
            items: [
              if (showFreight) ('Total Freight', inr(totalFreight)),
              ('Customers Active', '${customerCount.length}'),
              ('Vehicles Used', '${vehicleUtilization.length}'),
            ],
          ),
          SizedBox(height: gap),
          _BreakdownCard(
            title: 'Customer-wise LR count',
            icon: Icons.people_outline,
            items: customerCount.entries
                .map((e) => (e.key, '${e.value}'))
                .toList(),
          ),
          // Customer freight summary is transporter-side amount data — hidden
          // from operators and anyone lacking VIEW_TRANSPORTER_RATE.
          if (showFreight) ...[
            SizedBox(height: gap2),
            AppCard(
              padding: EdgeInsets.all(mobile ? 12 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Customer freight summary',
                  ),
                  for (final entry in customerFreight.entries)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: mobile ? 4 : 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
          ],
          SizedBox(height: gap2),
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
    final totalAdvance = lrs.fold<double>(0, (s, l) => s + l.freight.advance);
    final totalPending = lrs
        .where((l) => l.freight.balance > 0)
        .fold<double>(0, (s, l) => s + l.freight.balance);
    final margin = lrs.fold<double>(0, (s, l) => s + l.freight.vistarMargin);
    final mobile = MediaQuery.of(context).size.width < 600;
    final pad = mobile ? 14.0 : 28.0;
    final gap = mobile ? 10.0 : 20.0;
    // The MIS export carries accounts-owned billing / payment fields, so it's
    // limited to the accounts desk + super admins (and blocked server-side) —
    // operators and regional admins don't see it.
    final canViewMis = ref.watch(currentUserProvider)?.canViewAccounts ?? false;
    // This tab is only built when canViewAmounts is true, so the per-field
    // perms alone are the right gate here (no extra AND needed).
    final canT =
        ref.watch(currentUserProvider)?.canViewTransporterRate ?? false;
    final canMargin =
        ref.watch(currentUserProvider)?.canViewVistarMargin ?? false;
    final misRange = ref.watch(_misRangeProvider);
    final misRegion = ref.watch(_misRegionProvider);
    final misCreator = ref.watch(_misCreatorProvider);
    final misSent = ref.watch(_misSentProvider);
    // Derive the MIS filter options from the visible LRs. Region label = the
    // short code embedded in the LR number ({prefix}/{REGION}/{FY}/{seq});
    // creator label = the creator name (populated once /lrs returns it).
    final misRegions = <String, String>{}; // region_id -> short code
    final misCreators = <String, String>{}; // entered_by -> name
    for (final l in lrs) {
      final rid = l.regionId;
      if (rid != null && rid.isNotEmpty) {
        final parts = l.number.split('/');
        if (parts.length > 1 && RegExp(r'^[A-Za-z]{2,6}$').hasMatch(parts[1])) {
          misRegions[rid] = parts[1].toUpperCase();
        }
      }
      if (l.enteredBy.isNotEmpty && l.enteredByName.isNotEmpty) {
        misCreators[l.enteredBy] = l.enteredByName;
      }
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(
            items: [
              if (canT) ('Advance Received', inr(totalAdvance)),
              if (canT) ('Pending Freight', inr(totalPending)),
              if (canMargin) ('Margin (MTD)', inr(margin)),
            ],
          ),
          // The Tally ledger export is built client-side from freight amounts,
          // so the whole card is hidden without VIEW_TRANSPORTER_RATE.
          if (canT) ...[
            SizedBox(height: gap),
            AppCard(
              padding: EdgeInsets.all(mobile ? 12 : 20),
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
                            color: AppColors.slate,
                            fontSize: 13,
                          ),
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
                              content: Text('Tally-format file generated'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (canViewMis)
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: AppCard(
                padding: EdgeInsets.all(mobile ? 12 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      icon: Icons.table_view_outlined,
                      title: 'MIS report',
                    ),
                    Text(
                      misRange == null
                          ? 'Download the Transport Business Tracker MIS (Excel) — '
                              'all LRs with billing, payment and POD details.'
                          : 'MIS (Excel) for ${formatDate(misRange.start)} – '
                              '${formatDate(misRange.end)} — billing, payment '
                              'and POD details.',
                      style:
                          const TextStyle(color: AppColors.slate, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(now.year + 1, 12, 31),
                              initialDateRange: misRange,
                              helpText: 'MIS date range',
                              saveText: 'Apply',
                            );
                            if (picked != null) {
                              ref.read(_misRangeProvider.notifier).state =
                                  picked;
                            }
                          },
                          icon: const Icon(Icons.date_range_rounded, size: 16),
                          label: Text(
                            misRange == null
                                ? 'All dates'
                                : '${formatDate(misRange.start)} – '
                                    '${formatDate(misRange.end)}',
                          ),
                        ),
                        if (misRange != null)
                          TextButton(
                            onPressed: () => ref
                                .read(_misRangeProvider.notifier)
                                .state = null,
                            child: const Text('Clear'),
                          ),
                        if (misRegions.isNotEmpty)
                          SizedBox(
                            width: 170,
                            child: SearchableField<String>(
                              value: misRegion,
                              options: misRegions.keys.toList()
                                ..sort((a, b) =>
                                    misRegions[a]!.compareTo(misRegions[b]!)),
                              labelOf: (id) => misRegions[id] ?? id,
                              hintText: 'All regions',
                              dialogTitle: 'Region',
                              clearable: true,
                              onChanged: (v) => ref
                                  .read(_misRegionProvider.notifier)
                                  .state = v,
                            ),
                          ),
                        if (misCreators.isNotEmpty)
                          SizedBox(
                            width: 200,
                            child: SearchableField<String>(
                              value: misCreator,
                              options: misCreators.keys.toList()
                                ..sort((a, b) =>
                                    misCreators[a]!.compareTo(misCreators[b]!)),
                              labelOf: (id) => misCreators[id] ?? id,
                              hintText: 'All creators',
                              dialogTitle: 'Created by',
                              clearable: true,
                              onChanged: (v) => ref
                                  .read(_misCreatorProvider.notifier)
                                  .state = v,
                            ),
                          ),
                        // Payment-stage filter. Clearing it (the ✕) returns to
                        // "All LRs" — the default, unchanged download.
                        SizedBox(
                          width: 190,
                          child: SearchableField<bool>(
                            value: misSent,
                            options: const [true, false],
                            labelOf: (v) =>
                                v ? 'Sent for advance' : 'Not yet sent',
                            hintText: 'All LRs',
                            dialogTitle: 'Payment stage',
                            clearable: true,
                            onChanged: (v) =>
                                ref.read(_misSentProvider.notifier).state = v,
                          ),
                        ),
                        AppButton(
                          label: 'Download MIS (Excel)',
                          icon: Icons.download_outlined,
                          kind: BtnKind.primary,
                          small: true,
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final range = ref.read(_misRangeProvider);
                            try {
                              final bytes = await ref
                                  .read(reportsRepositoryProvider)
                                  .misXlsx(
                                    from: range?.start
                                        .toIso8601String()
                                        .substring(0, 10),
                                    to: range?.end
                                        .toIso8601String()
                                        .substring(0, 10),
                                    regionId: ref.read(_misRegionProvider),
                                    createdBy: ref.read(_misCreatorProvider),
                                    sentForPayment: ref.read(_misSentProvider),
                                  );
                              await ExportService.shareBytes(
                                bytes,
                                'Transport_MIS_${ExportService.stamp()}.xlsx',
                              );
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('MIS Excel generated'),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Could not generate MIS: $e'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
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
        final mobile = c.maxWidth < 600;
        // Fit all items in one row on mobile too (compact stat tiles).
        final cols = items.length;
        final spacing = mobile ? 8.0 : 16.0;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final s in items)
              SizedBox(
                width: (c.maxWidth - spacing * (cols - 1)) / cols,
                child: AppCard(
                  padding: EdgeInsets.all(mobile ? 11 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.$1,
                        maxLines: mobile ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.slate,
                          fontWeight: FontWeight.w700,
                          fontSize: mobile ? 11 : 12.5,
                        ),
                      ),
                      SizedBox(height: mobile ? 3 : 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          s.$2,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: mobile ? 18 : 22,
                            letterSpacing: -0.4,
                          ),
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
    final mobile = MediaQuery.of(context).size.width < 600;
    return AppCard(
      padding: EdgeInsets.all(mobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(icon: icon, title: title),
          for (final item in items)
            Padding(
              padding: EdgeInsets.symmetric(vertical: mobile ? 4 : 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
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
