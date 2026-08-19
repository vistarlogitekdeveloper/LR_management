import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/perf_log.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lr/providers/lr_providers.dart';
import '../../masters/providers/master_providers.dart';
import '../../shell/widgets/app_topbar.dart';

enum _PayFilter { all, awaitingAdvance, awaitingBalance, paid }

extension on _PayFilter {
  String get label => switch (this) {
    _PayFilter.all => 'All',
    _PayFilter.awaitingAdvance => 'Awaiting Advance',
    _PayFilter.awaitingBalance => 'Awaiting Balance',
    _PayFilter.paid => 'Paid',
  };
}

final _accountsFilterProvider = StateProvider<_PayFilter>(
  (ref) => _PayFilter.all,
);

// Free-text search over the LR payment list (LR no / party / vehicle / route).
final _accountsSearchProvider = StateProvider<String>((ref) => '');

// Optional date-range filter on the LR date. null = no date filter (a single
// day is a range with the same start & end).
final _accountsDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

// Region filter (region_id). null = all regions.
final _accountsRegionProvider = StateProvider<String?>((ref) => null);

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swTotal = kAccPerfLog ? (Stopwatch()..start()) : null;
    final sw = kAccPerfLog ? Stopwatch() : null;

    // Accounts only sees LRs an ops user has explicitly "sent for payment".
    // (Legacy LRs from before this feature default to sent, so nothing is lost.)
    sw?..reset()..start();
    final lrs = ref
        .watch(lrListProvider)
        .where((lr) => lr.sentForPayment)
        .toList();
    if (kAccPerfLog) {
      sw!.stop();
      accLog('[ACC-BUILD] sentForPayment ${sw.elapsedMicroseconds / 1000}ms '
          'n=${lrs.length}');
    }
    final loading = ref.watch(lrListLoadingProvider);
    final filter = ref.watch(_accountsFilterProvider);
    final query = ref.watch(_accountsSearchProvider).trim().toLowerCase();
    final range = ref.watch(_accountsDateRangeProvider);
    final region = ref.watch(_accountsRegionProvider);
    // Role visibility flags hoisted to the parent — every _LrPaymentCard used
    // to `ref.watch(currentUserProvider)` three times of its own, so with a
    // few hundred sent-for-payment LRs a single frame was doing hundreds of
    // provider subscriptions + rebuilds. Read them once here and pass down.
    final user = ref.watch(currentUserProvider);
    final canT = user?.canViewTransporterRate ?? false;
    final canCust = user?.canViewCustomerRate ?? false;
    final canMargin = user?.canViewVistarMargin ?? false;
    // Transporter lookup used to be an O(n) `.where(...).firstOrNull` per card;
    // for 500 cards × 200 transporters that's 100k comparisons per frame. Build
    // an id → transporter map once at the parent so each card is O(1).
    final transportersById = <String, Transporter>{
      for (final t in ref.watch(transportersProvider)) t.id: t,
    };
    final rangeStart = range == null ? null : DateUtils.dateOnly(range.start);
    final rangeEnd = range == null ? null : DateUtils.dateOnly(range.end);

    sw?..reset()..start();
    final sorted = [...lrs]..sort((a, b) => b.date.compareTo(a.date));
    // Region options (region_id -> short code embedded in the LR number) for
    // the region filter. Shown whenever at least one region is present.
    final regionCodes = <String, String>{};
    for (final lr in sorted) {
      final rid = lr.regionId;
      if (rid == null || rid.isEmpty) continue;
      final parts = lr.number.split('/');
      if (parts.length > 1 && RegExp(r'^[A-Za-z]{2,6}$').hasMatch(parts[1])) {
        regionCodes[rid] = parts[1].toUpperCase();
      }
    }
    final regionIds = regionCodes.keys.toList()
      ..sort((a, b) => regionCodes[a]!.compareTo(regionCodes[b]!));
    final hasRegions = regionIds.isNotEmpty;
    if (kAccPerfLog) {
      sw!.stop();
      accLog('[ACC-BUILD] sort+regionCodes ${sw.elapsedMicroseconds / 1000}ms '
          'n=${sorted.length}');
    }
    // Accounts pays the transporter, so payment state is tracked against the
    // transporter freight (the LR's advance % up front, the rest against POD),
    // not the customer
    // total. `balance` here means the transporter freight still unpaid.
    sw?..reset()..start();
    final filtered = sorted.where((lr) {
      final freight = lr.freight.freight;
      final balance = freight - lr.freight.advance;
      final matchesPay = switch (filter) {
        _PayFilter.all => true,
        _PayFilter.awaitingAdvance => lr.freight.advance <= 0 && freight > 0,
        _PayFilter.awaitingBalance => lr.freight.advance > 0 && balance > 0.01,
        _PayFilter.paid => freight > 0 && balance <= 0.01,
      };
      if (!matchesPay) return false;
      if (region != null && lr.regionId != region) return false;
      if (rangeStart != null) {
        final d = DateUtils.dateOnly(lr.date);
        if (d.isBefore(rangeStart) || d.isAfter(rangeEnd!)) return false;
      }
      if (query.isEmpty) return true;
      final hay = [
        lr.number,
        lr.consignor.name,
        lr.consignee.name,
        lr.customerName,
        lr.vehicle.number,
        lr.route,
        lr.transporter.name,
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
    if (kAccPerfLog) {
      sw!.stop();
      accLog('[ACC-BUILD] filter+search ${sw.elapsedMicroseconds / 1000}ms '
          'n=${filtered.length}');
    }

    sw?..reset()..start();
    final totalAdvance = lrs.fold<double>(0, (s, l) => s + l.freight.advance);
    final totalPending = lrs.fold<double>(0, (s, l) {
      final pend = l.freight.freight - l.freight.advance;
      return s + (pend > 0 ? pend : 0);
    });

    // Status counts — same buckets as the filter chips below.
    var countPending = 0; // awaiting advance (nothing paid)
    var countAdvancePaid = 0; // advance paid, balance against POD pending
    var countFullyPaid = 0; // advance + balance both settled
    for (final l in lrs) {
      final f = l.freight.freight;
      if (f <= 0) continue;
      final bal = f - l.freight.advance;
      if (l.freight.advance <= 0) {
        countPending++;
      } else if (bal > 0.01) {
        countAdvancePaid++;
      } else {
        countFullyPaid++;
      }
    }
    if (kAccPerfLog) {
      sw!.stop();
      accLog('[ACC-BUILD] kpis ${sw.elapsedMicroseconds / 1000}ms');
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    if (kAccPerfLog) {
      swTotal!.stop();
      accLog('[ACC-BUILD] total ${swTotal.elapsedMicroseconds / 1000}ms');
    }

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'Accounts & Billing',
            subtitle: 'Collect advance, settle balance on each LR',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 14 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final mobile = c.maxWidth < 600;
                      // Up to 5 tiles (2 money totals — hidden without
                      // VIEW_TRANSPORTER_RATE — + 3 status counts): all in a row
                      // on wide screens, 3-up on tablets, 2-up on phones.
                      final cols = c.maxWidth >= 1040
                          ? 5
                          : c.maxWidth >= 680
                          ? 3
                          : 2;
                      final gap = mobile ? 10.0 : 16.0;
                      final tiles = <Widget>[
                        if (canT)
                          _MiniTile(
                            label: 'Advance Received',
                            value: inr(totalAdvance),
                            icon: Icons.savings_outlined,
                            color: AppColors.ok,
                            compact: mobile,
                          ),
                        if (canT)
                          _MiniTile(
                            label: 'Pending Balance',
                            value: inr(totalPending),
                            icon: Icons.pending_actions_outlined,
                            color: AppColors.red,
                            compact: mobile,
                          ),
                        _MiniTile(
                          label: 'Pending',
                          value: '$countPending',
                          icon: Icons.hourglass_bottom,
                          color: AppColors.orange,
                          compact: mobile,
                        ),
                        _MiniTile(
                          label: 'Advance Paid',
                          value: '$countAdvancePaid',
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppColors.plum,
                          compact: mobile,
                        ),
                        _MiniTile(
                          label: 'Fully Paid',
                          value: '$countFullyPaid',
                          icon: Icons.task_alt,
                          color: AppColors.ok,
                          compact: mobile,
                        ),
                      ];
                      // Spread the tiles that actually render across the row so
                      // hiding the money totals doesn't leave a trailing gap.
                      final effCols = tiles.length < cols ? tiles.length : cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final t in tiles)
                            SizedBox(
                              width: (c.maxWidth - gap * (effCols - 1)) / effCols,
                              child: t,
                            ),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: isMobile ? 12 : 20),
                  AppCard(
                    padding: EdgeInsets.all(isMobile ? 12 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(
                          icon: Icons.receipt_long_outlined,
                          title: 'LR Payments',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.plum.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              filtered.length == lrs.length
                                  ? '${lrs.length} LRs'
                                  : '${filtered.length} of ${lrs.length} LRs',
                              style: const TextStyle(
                                color: AppColors.plum,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: isMobile ? 10 : 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: TextField(
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText:
                                    'Search LR, party, vehicle, route…',
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: AppColors.slate,
                                ),
                              ),
                              onChanged: (v) => ref
                                  .read(_accountsSearchProvider.notifier)
                                  .state = v,
                            ),
                          ),
                        ),
                        SizedBox(height: isMobile ? 10 : 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in _PayFilter.values)
                              _FilterChip(
                                label: f.label,
                                selected: filter == f,
                                onTap: () =>
                                    ref
                                            .read(
                                              _accountsFilterProvider.notifier,
                                            )
                                            .state =
                                        f,
                              ),
                            _DateRangeChip(
                              range: range,
                              onTap: () =>
                                  _pickDateRange(context, ref, range),
                              onClear: () => ref
                                  .read(_accountsDateRangeProvider.notifier)
                                  .state = null,
                            ),
                            if (hasRegions)
                              SizedBox(
                                width: 180,
                                child: SearchableField<String>(
                                  value: region,
                                  options: regionIds,
                                  labelOf: (id) => regionCodes[id] ?? id,
                                  hintText: 'All regions',
                                  dialogTitle: 'Region',
                                  clearable: true,
                                  onChanged: (v) => ref
                                      .read(_accountsRegionProvider.notifier)
                                      .state = v,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: isMobile ? 12 : 16),
                        if (loading && lrs.isEmpty)
                          // First fetch still running → shimmer, not the empty
                          // message (which would read as "nothing to pay").
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: ShimmerCards(cards: 4),
                          )
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'No LRs in this view',
                                style: TextStyle(
                                  color: AppColors.slate.withValues(
                                    alpha: 0.85,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        else
                          _LrPaymentsList(
                            items: filtered,
                            canT: canT,
                            canCust: canCust,
                            canMargin: canMargin,
                            transportersById: transportersById,
                            gap: isMobile ? 8 : 12,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(
    BuildContext context,
    WidgetRef ref,
    DateTimeRange? current,
  ) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: current,
      helpText: 'Filter LRs by date',
      saveText: 'Apply',
    );
    if (picked != null) {
      ref.read(_accountsDateRangeProvider.notifier).state = picked;
    }
  }
}

/// A pill that opens a date-range picker; when a range is set it shows it and a
/// clear (×). Sits alongside the payment-status filter chips.
class _DateRangeChip extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _DateRangeChip({
    required this.range,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final r = range;
    final active = r != null;
    final label =
        active ? '${formatDate(r.start)} – ${formatDate(r.end)}' : 'Date range';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.plum : AppColors.white,
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: active ? AppColors.plum : AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range_rounded,
                size: 15,
                color: active ? Colors.white : AppColors.slate,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(1),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Windowed list of LR payment cards. Each card is heavy (nested containers,
/// three amount blocks, an advance plan, incentive plan, MIS chips, bank card,
/// action buttons), so materialising all N cards in one frame stalls the main
/// thread for hundreds of ms once N passes ~100. Render only [_pageSize] cards
/// initially and extend the window as the outer page scroller nears the bottom
/// — same pattern the LR list table uses, and cheap to keep in sync because
/// the notifier still owns the full data.
class _LrPaymentsList extends ConsumerStatefulWidget {
  final List<LorryReceipt> items;
  final bool canT;
  final bool canCust;
  final bool canMargin;
  final Map<String, Transporter> transportersById;
  final double gap;
  const _LrPaymentsList({
    required this.items,
    required this.canT,
    required this.canCust,
    required this.canMargin,
    required this.transportersById,
    required this.gap,
  });

  @override
  ConsumerState<_LrPaymentsList> createState() => _LrPaymentsListState();
}

class _LrPaymentsListState extends ConsumerState<_LrPaymentsList> {
  // Cards are large; a smaller window than the LR-list table (which uses 50)
  // still fills the initial viewport but keeps first-paint fast.
  static const _pageSize = 25;
  int _visible = _pageSize;
  ScrollPosition? _outerPos;

  @override
  void initState() {
    super.initState();
    if (kAccPerfLog) accLog('[ACC-LIST] INIT');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The Accounts screen wraps everything in a SingleChildScrollView; hook
    // its ScrollPosition so we can extend the window as the user nears the
    // bottom instead of using a nested Scrollable (which would double-scroll).
    final pos = Scrollable.maybeOf(context)?.position;
    if (!identical(pos, _outerPos)) {
      _outerPos?.removeListener(_onOuterScroll);
      _outerPos = pos;
      _outerPos?.addListener(_onOuterScroll);
    }
  }

  @override
  void didUpdateWidget(covariant _LrPaymentsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset the window on a genuinely different result set (search / filter /
    // date change), but not when the same list just grows — the notifier's
    // progressive loading appends pages and resetting mid-scroll would snap
    // the user's position back to the top.
    final old = oldWidget.items;
    final now = widget.items;
    final headChanged = old.isEmpty != now.isEmpty ||
        (old.isNotEmpty && now.isNotEmpty && old.first.id != now.first.id);
    if (headChanged || now.length < old.length) {
      _visible = _pageSize;
    }
  }

  void _onOuterScroll() {
    final pos = _outerPos;
    if (pos == null || !pos.hasContentDimensions) return;
    if (kAccPerfLog) {
      accLog('[ACC-LIST] fire pixels=${pos.pixels.toStringAsFixed(0)},'
          'maxSE=${pos.maxScrollExtent.toStringAsFixed(0)},'
          'hasDims=${pos.hasContentDimensions}');
    }
    if (_visible >= widget.items.length) return;
    if (pos.pixels >= pos.maxScrollExtent - 800) {
      setState(() {
        final next = _visible + _pageSize;
        final to = next > widget.items.length ? widget.items.length : next;
        if (kAccPerfLog) accLog('[ACC-LIST] GROW $_visible->$to');
        _visible = to;
      });
    }
  }

  @override
  void dispose() {
    if (kAccPerfLog) accLog('[ACC-LIST] DISPOSE');
    _outerPos?.removeListener(_onOuterScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kAccPerfLog) accLog('[ACC-LIST] build visible=$_visible');
    final items = _visible >= widget.items.length
        ? widget.items
        : widget.items.take(_visible).toList();
    return Column(
      children: [
        for (final lr in items)
          Padding(
            padding: EdgeInsets.only(bottom: widget.gap),
            child: _LrPaymentCard(
              lr: lr,
              canT: widget.canT,
              canCust: widget.canCust,
              canMargin: widget.canMargin,
              transporter: widget.transportersById[lr.transporter.id],
            ),
          ),
      ],
    );
  }
}

class _LrPaymentCard extends ConsumerWidget {
  final LorryReceipt lr;
  // Role-visibility flags + transporter are hoisted from the parent so a
  // hundred cards don't each subscribe to currentUserProvider three times
  // (and re-scan transportersProvider) on every rebuild.
  final bool canT;
  final bool canCust;
  final bool canMargin;
  final Transporter? transporter;
  const _LrPaymentCard({
    required this.lr,
    required this.canT,
    required this.canCust,
    required this.canMargin,
    required this.transporter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Payment state is tracked against the transporter freight (the amount
    // Accounts pays out): the LR's advance % up front, the balance against POD.
    final freight = lr.freight.freight;
    final advance = lr.freight.advance;
    final transBalance = (freight - advance) > 0 ? (freight - advance) : 0.0;
    final hasAdvance = advance > 0;
    final hasBalance = transBalance > 0.01;
    final fullyPaid = freight > 0 && !hasBalance;

    final mobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    lr.number,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  StatusPill(status: lr.status),
                  if (fullyPaid)
                    const _BadgePill(text: 'Paid', fg: AppColors.ok)
                  else if (!hasAdvance)
                    const _BadgePill(
                      text: 'Awaiting Advance',
                      fg: AppColors.orange,
                    )
                  else
                    const _BadgePill(
                      text: 'Awaiting Balance',
                      fg: AppColors.red,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${lr.consignor.name} → ${lr.consignee.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              Text(
                '${formatDate(lr.date)} · ${lr.route}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.slate, fontSize: 12),
              ),
            ],
          );

          final amounts = Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Amount(
                label: 'Transporter Freight',
                value: freight,
                hidden: !canT,
              ),
              _Amount(
                label: 'Advance',
                value: advance,
                color: AppColors.ok,
                hidden: !canT,
              ),
              _Amount(
                label: 'Balance (after POD)',
                value: transBalance,
                color: hasBalance ? AppColors.red : AppColors.ok,
                emphasis: true,
                hidden: !canT,
              ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (!hasAdvance && lr.freight.freight > 0)
                AppButton(
                  label: 'Mark Advance Paid',
                  kind: BtnKind.soft,
                  icon: Icons.savings_outlined,
                  small: true,
                  onPressed: () => _markAdvancePaid(context, ref),
                ),
              if (hasAdvance && hasBalance)
                AppButton(
                  label: 'Add Advance',
                  kind: BtnKind.ghost,
                  icon: Icons.add_rounded,
                  small: true,
                  onPressed: () => _payAdvance(context, ref),
                ),
              if (hasBalance)
                AppButton(
                  label: 'Complete Payment',
                  kind: BtnKind.primary,
                  icon: Icons.check_circle_outline,
                  small: true,
                  onPressed: () => _completePayment(context, ref),
                ),
              if (fullyPaid)
                const _BadgePill(text: 'Settled', fg: AppColors.ok),
              AppButton(
                label: 'Billing / MIS',
                kind: BtnKind.ghost,
                icon: Icons.receipt_long_outlined,
                small: true,
                onPressed: () => _editBillingMis(context, ref),
              ),
            ],
          );

          final main = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: header),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: amounts),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: actions),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 12),
                    amounts,
                    const SizedBox(height: 12),
                    actions,
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              // The advance plan is a transporter-freight breakdown.
              if (canT) _advancePlan(context),
              // Client incentive charges: driver share is released with the
              // balance, so Accounts sees it alongside the advance plan.
              if (canT)
                _driverIncentivePlan(context, canViewVistarMargin: canMargin),
              _billingMisInfo(context, canViewCustomerRate: canCust),
              _payInfo(context, ref, transporter),
            ],
          );
        },
      ),
    );
  }

  /// Transporter payment / bank details for accounts to action the payout.
  Widget _payInfo(BuildContext context, WidgetRef ref, Transporter? t) {
    if (t == null) return const SizedBox.shrink();
    final hasBank =
        t.bankName.isNotEmpty || t.accountNo.isNotEmpty || t.ifsc.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.plum.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_outlined,
                size: 16,
                color: AppColors.plum,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pay to: ${t.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 13,
                  ),
                ),
              ),
              if (t.hasDocument)
                TextButton.icon(
                  onPressed: () => _viewCheque(context, ref, t),
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('Cheque'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (t.hasTdsDocument)
                TextButton.icon(
                  onPressed: () => _viewTds(context, ref, t),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('TDS'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (hasBank)
            Wrap(
              spacing: 18,
              runSpacing: 4,
              children: [
                if (t.bankName.isNotEmpty) _kvChip('Bank', t.bankName),
                if (t.accountHolder.isNotEmpty)
                  _kvChip('A/C Holder', t.accountHolder),
                if (t.accountNo.isNotEmpty) _kvChip('A/C No', t.accountNo),
                if (t.ifsc.isNotEmpty) _kvChip('IFSC', t.ifsc),
              ],
            )
          else
            const Text(
              'No bank details on this transporter — add them in the Transporter master.',
              style: TextStyle(color: AppColors.orange, fontSize: 11.5),
            ),
          _ocrVerify(t),
        ],
      ),
    );
  }

  /// This LR's advance share — copied from the transporter when the LR was
  /// created and overridable per LR (90 for every legacy LR, so their figures
  /// are unchanged). Clamped because it drives a payout preview.
  double get _advancePct => lr.freight.advancePercent.clamp(0, 100).toDouble();

  /// The advance share of the transporter freight, rounded to the nearest 1000
  /// so Accounts releases a clean round figure (e.g. 17,550 -> 18,000), clamped
  /// to the freight. The backend rounds the same way when the advance is paid —
  /// see markAdvancePaid in lrController.js, which must stay in lockstep with
  /// this, since this only PREVIEWS the number the server will compute.
  double _advanceFor(double freight) =>
      (((freight * (_advancePct / 100)) / 1000).roundToDouble() * 1000)
          .clamp(0, freight)
          .toDouble();

  /// The transporter advance plan: the LR's advance share of the transporter
  /// freight is released up front, the remainder settles after POD. The actual
  /// figures are computed on `freight` (the transporter freight, excluding the
  /// customer-side door/handling charges) — the same base Accounts pays out on.
  Widget _advancePlan(BuildContext context) {
    final freight = lr.freight.freight;
    if (freight <= 0) return const SizedBox.shrink();
    final advance = _advanceFor(freight); // rounded to 1000
    final afterPod = freight - advance; // balance against POD
    // "Advance done" once the recorded advance covers the rounded target;
    // "fully paid" once it covers the whole freight (balance also released).
    final advanceDone = lr.freight.advance + 0.5 >= advance;
    final fullyPaid = lr.freight.advance + 0.5 >= freight;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ok.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ok.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: AppColors.ok,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Transporter Advance Plan',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 13,
                  ),
                ),
              ),
              _BadgePill(
                text: fullyPaid
                    ? 'Fully Paid'
                    : advanceDone
                    ? 'Advance Paid'
                    : 'Advance Due',
                fg: (fullyPaid || advanceDone)
                    ? AppColors.ok
                    : AppColors.orange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Amount(label: 'Transporter Freight', value: freight),
              _Amount(
                label: 'Advance ${pctText(_advancePct)}% (now)',
                value: advance,
                color: AppColors.ok,
                emphasis: true,
              ),
              _Amount(
                label: 'Balance ${pctText(100 - _advancePct)}% (after POD)',
                value: afterPod,
                color: AppColors.slate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Client incentive charges (express / extra-point delivery). The driver's
  /// share is released together with the transporter balance (after POD); the
  /// remainder is Vistar margin. Shown so Accounts knows to add the driver
  /// incentive when completing the balance payment. Hidden when there's none.
  Widget _driverIncentivePlan(
    BuildContext context, {
    required bool canViewVistarMargin,
  }) {
    final client = lr.freight.clientIncentiveTotal;
    if (client <= 0) return const SizedBox.shrink();
    final driver = lr.freight.driverIncentiveTotal;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.plum.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volunteer_activism_outlined,
                size: 16,
                color: AppColors.plum,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Client Incentive — driver share paid with balance',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 13,
                  ),
                ),
              ),
              _BadgePill(
                text: lr.driverIncentivePaid ? 'Paid' : 'With Balance',
                fg: lr.driverIncentivePaid ? AppColors.ok : AppColors.plum,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Amount(label: 'Client Incentive', value: client),
              _Amount(
                label: 'Driver Share (pay with balance)',
                value: driver,
                color: AppColors.ok,
                emphasis: true,
              ),
              _Amount(
                label: 'Vistar Margin',
                value: lr.freight.incentiveVistarMargin,
                color: AppColors.slate,
                hidden: !canViewVistarMargin,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Read-only summary of the accounts-owned billing / MIS fields, shown only
  /// in the Accounts view. Empty (hidden) until Accounts fills them in.
  Widget _billingMisInfo(
    BuildContext context, {
    required bool canViewCustomerRate,
  }) {
    final chips = <Widget>[];
    // Bill No / Bill Date are customer-side billing fields (VIEW_CUSTOMER_RATE).
    if (canViewCustomerRate) {
      if (lr.vistarBillNo.isNotEmpty) {
        chips.add(_kvChip('Bill No', lr.vistarBillNo));
      }
      if (lr.vistarBillDate != null) {
        chips.add(_kvChip('Bill Date', formatDate(lr.vistarBillDate!)));
      }
    }
    if (lr.podSoftCopyDate != null) {
      chips.add(_kvChip('POD Recd', formatDate(lr.podSoftCopyDate!)));
    }
    if (lr.advancePaidAt != null) {
      chips.add(_kvChip('Adv Paid', formatDate(lr.advancePaidAt!)));
    }
    if (lr.balancePaidAt != null) {
      chips.add(_kvChip('Bal Paid', formatDate(lr.balancePaidAt!)));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Wrap(spacing: 16, runSpacing: 6, children: chips),
    );
  }

  /// Cheque-vs-entered verification badge from the background OCR.
  Widget _ocrVerify(Transporter t) {
    if (!t.ocrDone) return const SizedBox.shrink();
    final mismatch = t.ocrHasMismatch;
    final anyChecked =
        t.ifscMatchesOcr() != null || t.accountMatchesOcr() != null;
    if (!mismatch && !anyChecked) return const SizedBox.shrink();
    final color = mismatch ? AppColors.red : AppColors.ok;
    final icon = mismatch
        ? Icons.warning_amber_rounded
        : Icons.verified_outlined;
    final text = mismatch
        ? 'Cheque OCR mismatch — verify bank details before paying'
        : 'Bank details match the uploaded cheque';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvChip(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$k: ',
          style: const TextStyle(
            color: AppColors.slate,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Future<void> _viewCheque(
    BuildContext context,
    WidgetRef ref,
    Transporter t,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(transportersRepositoryProvider)
          .downloadDocument(t.id);
      final name = t.chequeFileName;
      openFileInBrowser(
        bytes,
        _mimeForName(name),
        name.isEmpty ? 'cheque' : name,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the document')),
      );
    }
  }

  Future<void> _viewTds(
    BuildContext context,
    WidgetRef ref,
    Transporter t,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(transportersRepositoryProvider)
          .downloadDocument(t.id, type: 'tds');
      final name = t.tdsFileName;
      openFileInBrowser(
        bytes,
        _mimeForName(name),
        name.isEmpty ? 'tds' : name,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the document')),
      );
    }
  }

  String _mimeForName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  /// Releases this LR's transporter advance and triggers the advance-paid
  /// notification email (LR creator + admins + master admin). The backend
  /// computes the amount from the transporter freight and the LR's own advance
  /// percentage — the figure shown here is a preview of that same calculation.
  Future<void> _markAdvancePaid(BuildContext context, WidgetRef ref) async {
    final freight = lr.freight.freight;
    final advance = _advanceFor(freight);
    final afterPod = freight - advance;
    final transporterName = lr.transporter.name.isEmpty
        ? 'the transporter'
        : lr.transporter.name;
    // Captured before the dialog await so we never touch context across the gap.
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Mark advance paid · ${lr.number}'),
            content: Text(
              'Release ${inr(advance)} (${pctText(_advancePct)}% of the transporter freight ${inr(freight)}) '
              'to $transporterName. The remaining ${inr(afterPod)} settles after POD.\n\n'
              'An advance-paid notification will be emailed to the LR creator, '
              'admin and master admin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark Paid & Notify'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref
          .read(lrListProvider.notifier)
          .markAdvancePaid(lr.id, lr.version);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Advance marked paid for ${lr.number} — notification email sent',
        ),
      ),
    );
  }

  Future<void> _payAdvance(BuildContext context, WidgetRef ref) async {
    final freight = lr.freight.freight;
    final outstanding = (freight - lr.freight.advance) > 0
        ? (freight - lr.freight.advance)
        : 0.0;
    final amount = await _showAmountDialog(
      context: context,
      title: 'Add Advance · ${lr.number}',
      message:
          'Outstanding ${inr(outstanding)} of transporter freight ${inr(freight)}.',
      max: outstanding,
      confirmLabel: 'Record Advance',
    );
    if (amount == null || amount <= 0) return;
    final newAdvance = (lr.freight.advance + amount)
        .clamp(0, freight)
        .toDouble();
    try {
      await ref.read(lrListProvider.notifier).updateLr(lr.id, lr.version, {
        'advance': newAdvance,
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Advance ${inr(amount)} recorded for ${lr.number}'),
      ),
    );
  }

  /// Releases the balance held against POD so the transporter is paid in full,
  /// and triggers the balance-paid notification email (LR creator + admins +
  /// master admin). The backend settles the amount (full transporter freight).
  Future<void> _completePayment(BuildContext context, WidgetRef ref) async {
    final freight = lr.freight.freight;
    final remaining = (freight - lr.freight.advance) > 0
        ? (freight - lr.freight.advance)
        : 0.0;
    final transporterName = lr.transporter.name.isEmpty
        ? 'the transporter'
        : lr.transporter.name;
    // Captured before the dialog await so we never touch context across the gap.
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Complete payment for ${lr.number}?'),
            content: Text(
              'Release the remaining balance ${inr(remaining)} to $transporterName '
              'against POD. Transporter freight ${inr(freight)} − advance '
              '${inr(lr.freight.advance)} = ${inr(remaining)}.\n\n'
              'A balance-paid notification will be emailed to the LR creator, '
              'admin and master admin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark Paid & Notify'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref
          .read(lrListProvider.notifier)
          .completePayment(lr.id, lr.version);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${lr.number} settled in full — notification email sent',
        ),
      ),
    );
  }

  /// Accounts-only editor for the MIS / billing fields: Vistar bill no & date,
  /// POD soft-copy date, and the advance/balance paid dates. Saved through the
  /// payment PATCH path, which the backend restricts to the Accounts role.
  Future<void> _editBillingMis(BuildContext context, WidgetRef ref) async {
    // Bill No / Bill Date are customer-side fields — hide their inputs from a
    // user without VIEW_CUSTOMER_RATE (the backend also strips them on save).
    final canViewCustomerRate =
        ref.read(currentUserProvider)?.canViewCustomerRate ?? false;
    final billNoCtrl = TextEditingController(text: lr.vistarBillNo);
    DateTime? billDate = lr.vistarBillDate;
    DateTime? podDate = lr.podSoftCopyDate;
    DateTime? advDate = lr.advancePaidAt;
    DateTime? balDate = lr.balancePaidAt;
    final messenger = ScaffoldMessenger.of(context);

    String fmt(DateTime? d) => d == null ? 'Not set' : formatDate(d);

    final saved =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> pick(
                DateTime? current,
                ValueChanged<DateTime> onPicked,
              ) async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: current ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setLocal(() => onPicked(picked));
              }

              Widget dateRow(
                String label,
                DateTime? value,
                ValueChanged<DateTime> onPicked,
                VoidCallback onClear,
              ) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$label: ${fmt(value)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () => pick(value, onPicked),
                        child: const Text('Pick'),
                      ),
                      if (value != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear',
                          onPressed: () => setLocal(onClear),
                        ),
                    ],
                  ),
                );
              }

              return AlertDialog(
                title: Text('Billing / MIS · ${lr.number}'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canViewCustomerRate) ...[
                        TextField(
                          controller: billNoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Vistar Bill No',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        dateRow(
                          'Vistar Bill Date',
                          billDate,
                          (d) => billDate = d,
                          () => billDate = null,
                        ),
                      ],
                      dateRow(
                        'POD Soft-Copy Date',
                        podDate,
                        (d) => podDate = d,
                        () => podDate = null,
                      ),
                      const Divider(),
                      dateRow(
                        'Advance Paid Date',
                        advDate,
                        (d) => advDate = d,
                        () => advDate = null,
                      ),
                      dateRow(
                        'Balance Paid Date',
                        balDate,
                        (d) => balDate = d,
                        () => balDate = null,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;

    if (!saved) return;

    String? dateOnly(DateTime? d) => d?.toIso8601String().substring(0, 10);
    final payload = <String, dynamic>{
      if (canViewCustomerRate) 'vistar_bill_no': billNoCtrl.text.trim(),
      if (canViewCustomerRate) 'vistar_bill_date': dateOnly(billDate),
      'pod_soft_copy_date': dateOnly(podDate),
      // Date-only (not full ISO) so the picked calendar day round-trips without
      // a timezone shift, same as the bill/POD dates above.
      'advance_paid_at': dateOnly(advDate),
      'balance_paid_at': dateOnly(balDate),
    };
    try {
      await ref
          .read(lrListProvider.notifier)
          .updateLr(lr.id, lr.version, payload);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Billing / MIS details saved for ${lr.number}')),
    );
  }
}

Future<double?> _showAmountDialog({
  required BuildContext context,
  required String title,
  required String message,
  required double max,
  required String confirmLabel,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<double>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                style: const TextStyle(color: AppColors.slate, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = double.tryParse(v ?? '');
                  if (value == null || value <= 0) {
                    return 'Enter a valid amount';
                  }
                  if (value > max + 0.01) {
                    return 'Cannot exceed ${inr(max)}';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, double.parse(controller.text));
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

class _Amount extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final bool emphasis;
  // Redact the amount to an em-dash when the user lacks VIEW_TRANSPORTER_RATE.
  final bool hidden;

  const _Amount({
    required this.label,
    required this.value,
    this.color,
    this.emphasis = false,
    this.hidden = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.slate,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hidden ? '—' : inr(value),
          style: TextStyle(
            color: color ?? AppColors.ink,
            fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
            fontSize: emphasis ? 16 : 14.5,
          ),
        ),
      ],
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  final Color fg;
  const _BadgePill({required this.text, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.plum
              : AppColors.plum.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.plum
                : AppColors.plum.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.white : AppColors.plum,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  const _MiniTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final box = compact ? 36.0 : 44.0;
    return AppCard(
      padding: EdgeInsets.all(compact ? 12 : 20),
      child: Row(
        children: [
          Container(
            width: box,
            height: box,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: compact ? 18 : 22),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 11.5 : 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 16 : 20,
                      letterSpacing: -0.3,
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
