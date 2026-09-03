import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lr/providers/lr_providers.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/providers/reports_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/local_dashboard_metrics.dart';
import '../models/role_flow.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final lrs = ref.watch(lrListProvider);
    final summary = ref.watch(dashboardSummaryProvider).valueOrNull;
    // First load with nothing to show yet → shimmer instead of a page full of
    // zeros that reads like real (empty) data.
    final firstLoading =
        ref.watch(lrListLoadingProvider) && lrs.isEmpty && summary == null;

    final flow = user == null ? null : RoleFlows.flows[user.role];
    final canCreate = user?.canCreateLr ?? false;
    // Vistar margin (VIEW_VISTAR_MARGIN) and transporter-side amounts
    // (VIEW_TRANSPORTER_RATE) are permission-driven (migration 072): every role
    // holds them by default, so they show unless a super admin revokes the perm.
    final showMargin = user?.canViewVistarMargin ?? false;
    final canViewTransporterRate = user?.canViewTransporterRate ?? false;

    // Six most recent LRs for the "Recent Lorry Receipts" list further down.
    final recentLrs = lrs.take(6).toList();

    // Tile figures come from the server (/reports/dashboard → `metrics`), which
    // computes today / MTD / total in IST and applies the viewer's region scope
    // and rate permissions in SQL. Deriving them here instead would only ever be
    // as correct as the page of LRs this client happens to hold.
    //
    // localDashboardMetrics() is a stand-in for one case only: an app build that
    // is ahead of the backend deploy, where `metrics` is absent from the
    // response. Then the tiles degrade in accuracy rather than going blank.
    final metrics = (summary != null && summary.metrics.isNotEmpty)
        ? summary.metrics
        : localDashboardMetrics(lrs);

    final marginMtd = lrs.fold<double>(
      0,
      (sum, lr) => sum + lr.freight.vistarMargin,
    );

    final customerTotals = <String, double>{};
    for (final lr in lrs) {
      // Rank by the LR's customer, not the consignor. Fall back to the
      // consignor only for older LRs that have no customer recorded, so no
      // freight is dropped from the ranking.
      final customer = lr.customerName.trim();
      final key = customer.isNotEmpty ? customer : lr.consignor.name;
      customerTotals[key] = (customerTotals[key] ?? 0) + lr.freight.total;
    }
    final topCustomers = customerTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFour = topCustomers.take(4).toList();
    final maxCust = topFour.isEmpty ? 1.0 : topFour.first.value;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Welcome, ${user?.name.split(' ').first ?? ''}',
            subtitle: user == null
                ? null
                : '${user.role.label} · ${flow?.tagline ?? ''}',
            actions: [
              AppButton(
                label: 'Live Tracking',
                icon: Icons.my_location_rounded,
                kind: BtnKind.ghost,
                onPressed: () => context.go('/tracking'),
              ),
              if (canCreate)
                AppButton(
                  label: 'New LR',
                  icon: Icons.add_rounded,
                  onPressed: () => context.go('/lrs/new'),
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 14 : 20,
              ),
              child: firstLoading
                  ? const ShimmerCards(cards: 6)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (flow != null) ...[
                          _RoleFlowStrip(flow: flow),
                          const SizedBox(height: 14),
                        ],
                        LayoutBuilder(
                          builder: (context, c) {
                            // Compact KPI tiles, four per row (two only when very
                            // narrow) — same small card on web and mobile.
                            final cols = c.maxWidth < 480 ? 2 : 4;
                            final spacing = c.maxWidth < 600 ? 8.0 : 12.0;
                            // Each tile drills into the matching filtered view. The
                            // LR-list filter is reset to only the relevant criterion
                            // so the destination shows exactly what the tile counts.
                            final now = DateTime.now();
                            final todayDate = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            void openLrs(LrFilter f) {
                              ref.read(lrFilterProvider.notifier).state = f;
                              context.go('/lrs');
                            }

                            // Tiles follow the operational funnel: booked → vehicle
                            // placed → dispatched → in transit → completed, then the
                            // two backlogs.
                            //
                            // Flow tiles headline Today (the day's output); the
                            // backlog tiles headline Total, because "pending" is a
                            // standing figure — the ₹ still owed across every open LR
                            // is the number being watched, not just today's slice.
                            final stats = <_StatTile>[
                              _StatTile(
                                icon: Icons.description_outlined,
                                tint: AppColors.plum,
                                label: 'LRs Booked',
                                metric: metrics['lrs_booked'],
                                headline: MetricScope.today,
                                onTap: () => openLrs(
                                  LrFilter(
                                    fromDate: todayDate,
                                    toDate: todayDate,
                                  ),
                                ),
                              ),
                              _StatTile(
                                icon: Icons.pin_drop_outlined,
                                tint: AppColors.plum,
                                label: 'Vehicle Placed',
                                metric: metrics['vehicles_placed'],
                                headline: MetricScope.today,
                                onTap: () => openLrs(
                                  LrFilter(
                                    fromDate: todayDate,
                                    toDate: todayDate,
                                  ),
                                ),
                              ),
                              _StatTile(
                                icon: Icons.local_shipping_outlined,
                                tint: AppColors.orange,
                                label: 'Vehicles Dispatched',
                                metric: metrics['vehicles_dispatched'],
                                headline: MetricScope.today,
                                onTap: () => openLrs(
                                  LrFilter(
                                    fromDate: todayDate,
                                    toDate: todayDate,
                                  ),
                                ),
                              ),
                              _StatTile(
                                icon: Icons.alt_route_rounded,
                                tint: AppColors.amber,
                                label: 'Trips in Transit',
                                metric: metrics['trips_in_transit'],
                                headline: MetricScope.total,
                                onTap: () => openLrs(
                                  const LrFilter(status: LrStatus.inTransit),
                                ),
                              ),
                              _StatTile(
                                icon: Icons.task_alt_rounded,
                                tint: AppColors.ok,
                                label: 'Trips Completed',
                                metric: metrics['trips_completed'],
                                headline: MetricScope.today,
                                onTap: () => openLrs(
                                  const LrFilter(status: LrStatus.delivered),
                                ),
                              ),
                              _StatTile(
                                icon: Icons.schedule_rounded,
                                tint: AppColors.amber,
                                label: 'Pending Delivery',
                                // Booked + In Transit — everything not yet delivered,
                                // deliberately wider than Trips in Transit.
                                metric: metrics['pending_delivery'],
                                headline: MetricScope.total,
                                onTap: () => openLrs(
                                  const LrFilter(status: LrStatus.booked),
                                ),
                              ),
                              // Money tile: the server omits `pending_freight`
                              // entirely without VIEW_TRANSPORTER_RATE, so this is
                              // gated on the permission AND renders nothing if the
                              // metric never arrived.
                              if (canViewTransporterRate)
                                _StatTile(
                                  icon: Icons.account_balance_wallet_outlined,
                                  tint: AppColors.red,
                                  label: 'Pending Freight',
                                  metric: metrics['pending_freight'],
                                  headline: MetricScope.total,
                                  money: true,
                                  // Accounts desk gets the payments queue; everyone
                                  // else (who can see the amount) gets the LR list.
                                  onTap: () {
                                    if (user?.canViewAccounts ?? false) {
                                      context.go('/accounts');
                                    } else {
                                      openLrs(const LrFilter());
                                    }
                                  },
                                ),
                            ];
                            // Distribute the tiles that actually render across the
                            // row — a gated-out tile shouldn't leave a blank slot.
                            final effCols = stats.length < cols
                                ? stats.length
                                : cols;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                for (final s in stats)
                                  SizedBox(
                                    width:
                                        (c.maxWidth - spacing * (effCols - 1)) /
                                        effCols,
                                    child: s,
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth >= 1100;
                            final left = AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SectionTitle(
                                    icon: Icons.history_rounded,
                                    title: 'Recent Lorry Receipts',
                                    trailing: TextButton(
                                      onPressed: () => context.go('/lrs'),
                                      child: const Text('View all'),
                                    ),
                                  ),
                                  for (final lr in recentLrs)
                                    _RecentLrRow(
                                      lr: lr,
                                      canViewTransporterRate:
                                          canViewTransporterRate,
                                    ),
                                ],
                              ),
                            );
                            // Right column (Top Customers + Vistar margin) only exists
                            // if the viewer can see at least one of them; otherwise the
                            // Recent LRs card takes the full width instead of pairing
                            // with an empty Expanded.
                            final hasSide =
                                canViewTransporterRate || showMargin;
                            if (!hasSide) return left;
                            final right = Column(
                              children: [
                                AppCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Top Customers ranks per-customer freight
                                      // totals (transporter-side amount).
                                      if (canViewTransporterRate) ...[
                                        const SectionTitle(
                                          icon: Icons.trending_up_rounded,
                                          title: 'Top Customers',
                                        ),
                                        for (final entry in topFour)
                                          _TopCustomerRow(
                                            name: entry.key,
                                            value: entry.value,
                                            max: maxCust,
                                          ),
                                      ],
                                      if (showMargin) ...[
                                        if (canViewTransporterRate)
                                          const SizedBox(height: 16),
                                        _MarginCard(
                                          margin: marginMtd,
                                          consignments: lrs.length,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: left),
                                  const SizedBox(width: 16),
                                  Expanded(flex: 2, child: right),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                left,
                                const SizedBox(height: 16),
                                right,
                              ],
                            );
                          },
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

class _RoleFlowStrip extends StatelessWidget {
  final RoleFlow flow;
  const _RoleFlowStrip({required this.flow});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.alt_route_rounded,
            title: 'Your workflow',
          ),
          LayoutBuilder(
            builder: (context, c) {
              // Compact step cards in one equal-width row at every width
              // (chevrons between on wider screens) — minimal vertical space.
              final wide = c.maxWidth >= 600;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < flow.steps.length; i++) ...[
                    if (i > 0) SizedBox(width: wide ? 2 : 6),
                    Expanded(
                      child: _FlowStepCard(
                        step: flow.steps[i],
                        index: i + 1,
                        compact: true,
                      ),
                    ),
                    if (wide && i < flow.steps.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.line,
                          size: 20,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FlowStepCard extends StatelessWidget {
  final FlowStep step;
  final int index;
  final bool compact;
  const _FlowStepCard({
    required this.step,
    required this.index,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        onTap: () => context.go(step.path),
        child: Container(
          padding: EdgeInsets.all(compact ? 6 : 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
          ),
          child: compact ? _compact() : _full(),
        ),
      ),
    );
  }

  // Tiny card for phones: icon + step-number badge over a 2-line title.
  Widget _compact() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: step.tint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(step.icon, size: 15, color: step.tint),
                ),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: step.tint,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 24,
          child: Center(
            child: Text(
              step.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                fontSize: 9.5,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _full() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: step.tint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: step.tint.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(step.icon, size: 18, color: step.tint),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          step.title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          step.desc,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Which of the three reported scopes a tile leads with.
enum MetricScope { today, mtd, total }

extension on MetricScope {
  String get label => switch (this) {
    MetricScope.today => 'Today',
    MetricScope.mtd => 'MTD',
    MetricScope.total => 'Total',
  };

  double read(MetricScopes m) => switch (this) {
    MetricScope.today => m.today,
    MetricScope.mtd => m.mtd,
    MetricScope.total => m.total,
  };
}

/// A KPI tile reporting one metric across Today / MTD / Total.
///
/// The `headline` scope is rendered large; the other two follow as a footer in
/// canonical (today → mtd → total) order, so every tile reads the same way even
/// though flow tiles lead with Today and backlog tiles lead with Total.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;

  /// Null while the summary is still loading, or when the viewer's permissions
  /// mean the server never sent this metric — rendered as em-dashes either way.
  final MetricScopes? metric;
  final MetricScope headline;

  /// Format values as ₹ rather than plain counts.
  final bool money;
  final VoidCallback? onTap;

  const _StatTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.metric,
    required this.headline,
    this.money = false,
    this.onTap,
  });

  String _fmt(double v) => money ? inr(v) : v.round().toString();

  @override
  Widget build(BuildContext context) {
    final m = metric;
    final rest = MetricScope.values.where((s) => s != headline).toList();

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: tint, size: 15),
              ),
              const SizedBox(height: 6),
              // Headline value. Money figures (₹79,69,378) are far wider than
              // counts, so it scales down rather than overflowing the tile.
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    m == null ? '—' : _fmt(headline.read(m)),
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 24,
                child: Text(
                  '$label · ${headline.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                    height: 1.1,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, thickness: 1, color: AppColors.line),
              ),
              for (final s in rest)
                _ScopeRow(
                  label: s.label,
                  value: m == null ? '—' : _fmt(s.read(m)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "MTD ——— 414" line under a tile's headline figure.
class _ScopeRow extends StatelessWidget {
  final String label;
  final String value;
  const _ScopeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontWeight: FontWeight.w600,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 4),
          // The value takes the leftover width and scales down inside it, so a
          // long ₹ figure shrinks instead of pushing the label off the tile.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentLrRow extends StatelessWidget {
  final LorryReceipt lr;
  final bool canViewTransporterRate;
  const _RecentLrRow({required this.lr, this.canViewTransporterRate = false});

  @override
  Widget build(BuildContext context) {
    final cleared = lr.freight.balance <= 0;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.go('/lrs/${lr.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.plum.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.description_outlined,
                size: 18,
                color: AppColors.plum,
              ),
            ),
            const SizedBox(width: 12),
            // Left zone flexes: number / parties / date stacked so the number
            // never gets crushed into a one-character-per-line column.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lr.number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lr.consignor.name} → ${lr.consignee.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDate(lr.date),
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Right zone stays compact: status over the balance.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(status: lr.status),
                const SizedBox(height: 6),
                Text(
                  !canViewTransporterRate
                      ? '—'
                      : (cleared ? 'Cleared' : inr(lr.freight.balance)),
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cleared ? AppColors.ok : AppColors.red,
                    fontSize: 12.5,
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

class _TopCustomerRow extends StatelessWidget {
  final String name;
  final double value;
  final double max;
  const _TopCustomerRow({
    required this.name,
    required this.value,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                inr(value),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(999),
            ),
            child: LayoutBuilder(
              builder: (_, c) {
                final w = max <= 0 ? 0.0 : c.maxWidth * (value / max);
                return Stack(
                  children: [
                    Container(
                      width: w,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MarginCard extends StatelessWidget {
  final double margin;
  final int consignments;
  const _MarginCard({required this.margin, required this.consignments});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.plum, AppColors.plumDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vistar Margin (MTD)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            inr(margin),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Across $consignments consignments',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
