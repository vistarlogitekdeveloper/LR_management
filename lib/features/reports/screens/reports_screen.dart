import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
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
import '../data/reports_repository.dart';
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

// Profit & Loss filters: region, year, and an optional month. A null month means
// the whole financial year (Apr year – Mar year+1); a month means that calendar
// month. Options for the P&L card in the Accounts tab.
final _plRegionProvider = StateProvider<String?>((ref) => null);
final _plYearProvider = StateProvider<int>((ref) => DateTime.now().year);
final _plMonthProvider = StateProvider<int?>((ref) => null);
// Optional custom inclusive date range. When set it OVERRIDES year/month, so the
// user can pull an arbitrary span (e.g. 15 May – 15 Jun). null = use year/month.
final _plRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

const _plMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String _plMonthName(int m) => _plMonthNames[(m - 1).clamp(0, 11)];

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
  // Date range chosen in the "Download Excel" dialog; null = all dates. Kept so
  // the picker reopens on the last range the user exported.
  DateTimeRange? _exportRange;

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
            subtitle: _canAmounts
                ? 'Daily · Monthly · Accounts'
                : 'Daily · Monthly',
            actions: [
              AppButton(
                label: 'Download Excel',
                icon: Icons.file_download_outlined,
                kind: BtnKind.soft,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  // Ask for an optional date range first — the sheet then holds
                  // only the LRs dispatched inside it (null = every LR).
                  final choice = await showDialog<_ExportRangeChoice>(
                    context: context,
                    builder: (_) => _ExportRangeDialog(
                      lrs: lrs,
                      initialRange: _exportRange,
                    ),
                  );
                  if (choice == null) return; // cancelled
                  setState(() => _exportRange = choice.range);
                  final rows = lrsInExportRange(lrs, choice.range);
                  if (rows.isEmpty) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('No LRs in the selected date range'),
                      ),
                    );
                    return;
                  }
                  await ExportService.exportLrsExcel(
                    rows,
                    canViewTransporterRate: _showFreight,
                    canViewVistarMargin: _showMargin,
                    filenameSuffix: choice.range == null
                        ? null
                        : '${_fileStamp(choice.range!.start)}-'
                              '${_fileStamp(choice.range!.end)}',
                  );
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        choice.range == null
                            ? '${rows.length} LRs exported as Excel'
                            : '${rows.length} LRs exported for '
                                  '${formatDate(choice.range!.start)} – '
                                  '${formatDate(choice.range!.end)}',
                      ),
                    ),
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
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
    final plRegion = ref.watch(_plRegionProvider);
    final plMonth = ref.watch(_plMonthProvider);
    final plYear = ref.watch(_plYearProvider);
    final plRange = ref.watch(_plRangeProvider);
    final plNowYear = DateTime.now().year;
    final plYears = [for (var y = plNowYear + 1; y >= plNowYear - 3; y--) y];
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
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 13,
                      ),
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
                            onPressed: () =>
                                ref.read(_misRangeProvider.notifier).state =
                                    null,
                            child: const Text('Clear'),
                          ),
                        if (misRegions.isNotEmpty)
                          SizedBox(
                            width: 170,
                            child: SearchableField<String>(
                              value: misRegion,
                              options: misRegions.keys.toList()
                                ..sort(
                                  (a, b) =>
                                      misRegions[a]!.compareTo(misRegions[b]!),
                                ),
                              labelOf: (id) => misRegions[id] ?? id,
                              hintText: 'All regions',
                              dialogTitle: 'Region',
                              clearable: true,
                              onChanged: (v) =>
                                  ref.read(_misRegionProvider.notifier).state =
                                      v,
                            ),
                          ),
                        if (misCreators.isNotEmpty)
                          SizedBox(
                            width: 200,
                            child: SearchableField<String>(
                              value: misCreator,
                              options: misCreators.keys.toList()
                                ..sort(
                                  (a, b) => misCreators[a]!.compareTo(
                                    misCreators[b]!,
                                  ),
                                ),
                              labelOf: (id) => misCreators[id] ?? id,
                              hintText: 'All creators',
                              dialogTitle: 'Created by',
                              clearable: true,
                              onChanged: (v) =>
                                  ref.read(_misCreatorProvider.notifier).state =
                                      v,
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
                                    to: range?.end.toIso8601String().substring(
                                      0,
                                      10,
                                    ),
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
                        // The reverse trip: fill the Accounts-owned columns in
                        // the downloaded sheet and push them back in.
                        AppButton(
                          label: 'Upload updated MIS',
                          icon: Icons.upload_file_outlined,
                          kind: BtnKind.soft,
                          small: true,
                          onPressed: () => _uploadMis(context, ref),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Fill in Balance Paid Date, Vistar Bill No and Vistar '
                      'Bill Date in the downloaded sheet and upload it back — '
                      'those three columns are saved against each LR (matched '
                      'on LR No) and appear in every later download. Blank '
                      'cells are left untouched, and every other column in the '
                      'sheet is read-only.',
                      style: TextStyle(
                        color: AppColors.slate.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (canViewMis)
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: AppCard(
                padding: EdgeInsets.all(mobile ? 12 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Profit & Loss (Transport)',
                    ),
                    Text(
                      plRange != null
                          ? 'Profit & Loss (Excel) for '
                                '${formatDate(plRange.start)} – ${formatDate(plRange.end)} — '
                                'sales, transport cost, gross & net profit per customer'
                                '${plRange.start.month != plRange.end.month || plRange.start.year != plRange.end.year ? ', plus a detailed sheet for each month in the range.' : '.'}'
                          : plMonth == null
                          ? 'Download Profit & Loss (Excel) for the financial year '
                                'Apr $plYear – Mar ${plYear + 1} — sales, transport cost, '
                                'gross & net profit per customer, a monthly summary, and '
                                'a separate detailed sheet for each month.'
                          : 'Profit & Loss (Excel) for ${_plMonthName(plMonth)} $plYear — '
                                'sales, transport cost, gross & net profit per customer.',
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Includes only LRs whose advance or full payment has been '
                      'marked paid — so the figures reflect realised business.',
                      style: TextStyle(
                        color: AppColors.slate.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Custom inclusive date range — overrides Year/Month
                        // when set (e.g. 15 May – 15 Jun).
                        OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(now.year + 1, 12, 31),
                              initialDateRange: plRange,
                              helpText: 'P&L date range',
                              saveText: 'Apply',
                            );
                            if (picked != null) {
                              ref.read(_plRangeProvider.notifier).state =
                                  picked;
                            }
                          },
                          icon: const Icon(Icons.date_range_rounded, size: 16),
                          label: Text(
                            plRange == null
                                ? 'Custom range'
                                : '${formatDate(plRange.start)} – '
                                      '${formatDate(plRange.end)}',
                          ),
                        ),
                        if (plRange != null)
                          TextButton(
                            onPressed: () =>
                                ref.read(_plRangeProvider.notifier).state =
                                    null,
                            child: const Text('Clear'),
                          ),
                        // Year / Month are ignored while a custom range is set.
                        if (plRange == null) ...[
                          SizedBox(
                            width: 120,
                            child: SearchableField<int>(
                              value: plYear,
                              options: plYears,
                              labelOf: (y) => '$y',
                              hintText: 'Year',
                              dialogTitle: 'Year',
                              onChanged: (v) {
                                if (v != null) {
                                  ref.read(_plYearProvider.notifier).state = v;
                                }
                              },
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: SearchableField<int>(
                              value: plMonth,
                              options: const [
                                1,
                                2,
                                3,
                                4,
                                5,
                                6,
                                7,
                                8,
                                9,
                                10,
                                11,
                                12,
                              ],
                              labelOf: _plMonthName,
                              hintText: 'Full year (FY)',
                              dialogTitle: 'Month',
                              clearable: true,
                              onChanged: (v) =>
                                  ref.read(_plMonthProvider.notifier).state = v,
                            ),
                          ),
                        ],
                        if (misRegions.isNotEmpty)
                          SizedBox(
                            width: 170,
                            child: SearchableField<String>(
                              value: plRegion,
                              options: misRegions.keys.toList()
                                ..sort(
                                  (a, b) =>
                                      misRegions[a]!.compareTo(misRegions[b]!),
                                ),
                              labelOf: (id) => misRegions[id] ?? id,
                              hintText: 'All regions',
                              dialogTitle: 'Region',
                              clearable: true,
                              onChanged: (v) =>
                                  ref.read(_plRegionProvider.notifier).state =
                                      v,
                            ),
                          ),
                        AppButton(
                          label: 'Download P&L (Excel)',
                          icon: Icons.download_outlined,
                          kind: BtnKind.primary,
                          small: true,
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final range = ref.read(_plRangeProvider);
                            final m = ref.read(_plMonthProvider);
                            final y = ref.read(_plYearProvider);
                            String ymd(DateTime d) =>
                                d.toIso8601String().substring(0, 10);
                            try {
                              final bytes = await ref
                                  .read(reportsRepositoryProvider)
                                  .profitLossXlsx(
                                    regionId: ref.read(_plRegionProvider),
                                    // A custom range wins; else month/year.
                                    from: range != null
                                        ? ymd(range.start)
                                        : null,
                                    to: range != null ? ymd(range.end) : null,
                                    month: range == null && m != null
                                        ? '$y-${m.toString().padLeft(2, '0')}'
                                        : null,
                                    year: range == null && m == null
                                        ? '$y'
                                        : null,
                                  );
                              await ExportService.shareBytes(
                                bytes,
                                'Profit_Loss_${ExportService.stamp()}.xlsx',
                              );
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Profit & Loss Excel generated',
                                  ),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Could not generate P&L: $e'),
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

  /// Picks a filled-in MIS workbook and pushes its Accounts-owned columns back
  /// into the app. Two server round-trips: a dry run that parses and diffs
  /// without writing (shown as a confirmation preview, so nobody commits a
  /// mis-edited sheet blind), then the real write once the user approves.
  Future<void> _uploadMis(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      // Bytes, not a path: web has no filesystem path, and the file is posted
      // straight through rather than kept.
      withData: true,
      dialogTitle: 'Select the filled-in MIS workbook',
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read that file — try again.')),
      );
      return;
    }

    final repo = ref.read(reportsRepositoryProvider);
    final MisImportResult preview;
    try {
      preview = await repo.importMisXlsx(
        bytes: bytes,
        filename: file.name,
        dryRun: true,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not read the MIS: ${friendlyErrorMessage(e)}'),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MisImportDialog(result: preview, filename: file.name),
    );
    if (confirmed != true || !context.mounted) return;

    // The write is sequential server-side and can run for a while on a big
    // sheet, so block the UI with a spinner rather than leaving the button
    // looking idle.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Saving MIS updates…')),
          ],
        ),
      ),
    );

    MisImportResult? applied;
    Object? failure;
    try {
      applied = await repo.importMisXlsx(bytes: bytes, filename: file.name);
    } catch (e) {
      failure = e;
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the spinner

    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('MIS upload failed: ${friendlyErrorMessage(failure)}'),
        ),
      );
      return;
    }

    // Pull the LRs back down so the Accounts list (and the next MIS download)
    // shows the values that were just written.
    await ref.read(lrListProvider.notifier).refresh(force: true);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MisImportDialog(result: applied!, filename: file.name),
    );
  }
}

/// Renders a MIS import summary. Doubles as the pre-write confirmation (when
/// `result.dryRun`, with Cancel / Apply actions) and the post-write receipt,
/// since the server returns the same shape for both.
class _MisImportDialog extends StatelessWidget {
  final MisImportResult result;
  final String filename;

  const _MisImportDialog({required this.result, required this.filename});

  @override
  Widget build(BuildContext context) {
    final dry = result.dryRun;
    final nothingToDo = !result.hasWork;
    return AlertDialog(
      title: Text(dry ? 'Review MIS updates' : 'MIS upload complete'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              _stat(
                dry ? 'LRs to update' : 'LRs updated',
                result.updatedCount,
                AppColors.plum,
              ),
              _stat(
                'Rows read from the sheet',
                result.rowsRead,
                AppColors.slate,
              ),
              _stat(
                'Already up to date',
                result.unchangedCount,
                AppColors.slate,
              ),
              if (result.notFoundCount > 0)
                _stat('LR No not found', result.notFoundCount, Colors.orange),
              if (result.errorCount > 0)
                _stat('Rows with problems', result.errorCount, Colors.red),
              if (result.ignoredColumns.isNotEmpty) ...[
                const SizedBox(height: 10),
                _note(
                  'Ignored (you do not have permission to change these): '
                  '${result.ignoredColumns.join(', ')}.',
                  Colors.orange,
                ),
              ],
              if (nothingToDo) ...[
                const SizedBox(height: 10),
                _note(
                  result.rowsWithValues == 0
                      ? 'None of the editable columns had a value in them, so '
                            'there is nothing to save.'
                      : 'Every value in the sheet already matches what is '
                            'stored, so there is nothing to save.',
                  AppColors.slate,
                ),
              ],
              if (result.updated.isNotEmpty)
                _rowList(
                  dry ? 'Will change' : 'Changed',
                  result.updated,
                  (r) => r.changes.map((c) => c.summary).join('  ·  '),
                  result.updatedCount,
                ),
              if (result.notFound.isNotEmpty)
                _rowList(
                  'No such LR (skipped)',
                  result.notFound,
                  (_) =>
                      'not in your LRs — check the LR No, or it may belong '
                      'to another region',
                  result.notFoundCount,
                ),
              if (result.errors.isNotEmpty)
                _rowList(
                  'Problems (skipped)',
                  result.errors,
                  (r) => r.message ?? '',
                  result.errorCount,
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (dry && !nothingToDo) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Save ${result.updatedCount} '
              '${result.updatedCount == 1 ? 'LR' : 'LRs'}',
            ),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
      ],
    );
  }

  static Widget _stat(String label, int value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  static Widget _note(String text, Color color) =>
      Text(text, style: TextStyle(fontSize: 11.5, color: color));

  /// A collapsed list of affected rows. Only the first 200 of each kind come
  /// back from the server, so say so when the count runs past what's shown.
  static Widget _rowList(
    String title,
    List<MisImportRow> rows,
    String Function(MisImportRow) detail,
    int total,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            '$title ($total)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'Row ${r.row} · ${r.lrNo} — ${detail(r)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  );
                },
              ),
            ),
            if (total > rows.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '…and ${total - rows.length} more',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
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

/// LRs whose dispatch date falls inside [range] (both ends inclusive, whole
/// days). A null range means "no filter" — every LR is exported.
List<LorryReceipt> lrsInExportRange(
  List<LorryReceipt> lrs,
  DateTimeRange? range,
) {
  if (range == null) return lrs;
  final from = DateTime(range.start.year, range.start.month, range.start.day);
  final to = DateTime(
    range.end.year,
    range.end.month,
    range.end.day,
  ).add(const Duration(days: 1));
  return lrs
      .where((lr) => !lr.date.isBefore(from) && lr.date.isBefore(to))
      .toList();
}

String _fileStamp(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// Result of [_ExportRangeDialog] — a wrapper so a null [range] ("All dates")
/// stays distinguishable from a cancelled dialog.
class _ExportRangeChoice {
  final DateTimeRange? range;
  const _ExportRangeChoice(this.range);
}

/// Date-range chooser shown before the Reports "Download Excel" export.
class _ExportRangeDialog extends StatefulWidget {
  final List<LorryReceipt> lrs;
  final DateTimeRange? initialRange;
  const _ExportRangeDialog({required this.lrs, this.initialRange});

  @override
  State<_ExportRangeDialog> createState() => _ExportRangeDialogState();
}

class _ExportRangeDialogState extends State<_ExportRangeDialog> {
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Export date range',
      saveText: 'Apply',
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final count = lrsInExportRange(widget.lrs, _range).length;
    return AlertDialog(
      title: const Text('Download Excel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pick a date range, or export every LR.',
            style: TextStyle(color: AppColors.slate, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.date_range_rounded, size: 16),
                label: Text(
                  _range == null
                      ? 'All dates'
                      : '${formatDate(_range!.start)} – '
                            '${formatDate(_range!.end)}',
                ),
              ),
              if (_range != null)
                TextButton(
                  onPressed: () => setState(() => _range = null),
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$count of ${widget.lrs.length} LRs will be exported.',
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: count == 0
              ? null
              : () => Navigator.pop(context, _ExportRangeChoice(_range)),
          child: const Text('Download'),
        ),
      ],
    );
  }
}
