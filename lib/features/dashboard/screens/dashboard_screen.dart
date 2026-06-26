import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lr/providers/lr_providers.dart';
import '../../reports/providers/reports_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../models/role_flow.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final lrs = ref.watch(lrListProvider);
    final summary = ref.watch(dashboardSummaryProvider).valueOrNull;

    final flow = user == null ? null : RoleFlows.flows[user.role];
    final canCreate = user?.canCreateLr ?? false;
    // Vistar margin is an internal profit figure — hide it from operators.
    final showMargin = user?.role != UserRole.operator;

    final today = lrs.take(6).toList();
    final pendingFreightLocal = lrs
        .where((lr) => lr.freight.balance > 0)
        .fold<double>(0, (sum, lr) => sum + lr.freight.balance);
    final inTransitLocal = lrs
        .where((lr) => lr.status == LrStatus.inTransit)
        .length;
    final dispatched = lrs.where((lr) => lr.status != LrStatus.booked).length;

    // Prefer server-side aggregates when the summary has loaded; otherwise fall
    // back to values computed from the live LR list.
    final pendingFreight = summary?.outstanding ?? pendingFreightLocal;
    final inTransit = summary == null
        ? inTransitLocal
        : (summary.byStatus['IN_TRANSIT'] ?? 0);
    final totalLrCount = summary?.count ?? lrs.length;
    final todayCount = summary?.count ?? today.length;
    final marginMtd = lrs.fold<double>(
      0,
      (sum, lr) => sum + lr.freight.vistarMargin,
    );

    final customerTotals = <String, double>{};
    for (final lr in lrs) {
      final key = lr.consignor.name;
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
                MediaQuery.of(context).size.width < 600 ? 14 : 20,
              ),
              child: Column(
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
                      final stats = <_StatTile>[
                        _StatTile(
                          icon: Icons.description_outlined,
                          tint: AppColors.plum,
                          label: 'Today\'s LR',
                          value: '$todayCount',
                          sub: '$totalLrCount total in system',
                          compact: true,
                        ),
                        _StatTile(
                          icon: Icons.local_shipping_outlined,
                          tint: AppColors.orange,
                          label: 'Vehicles Dispatched',
                          value: '$dispatched',
                          sub: '$inTransit in transit',
                          compact: true,
                        ),
                        _StatTile(
                          icon: Icons.schedule_rounded,
                          tint: AppColors.amber,
                          label: 'Pending Delivery',
                          value: '$inTransit',
                          sub: 'On the road',
                          compact: true,
                        ),
                        _StatTile(
                          icon: Icons.account_balance_wallet_outlined,
                          tint: AppColors.red,
                          label: 'Pending Freight',
                          value: inr(pendingFreight),
                          sub: 'across open LRs',
                          compact: true,
                        ),
                      ];
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final s in stats)
                            SizedBox(
                              width: (c.maxWidth - spacing * (cols - 1)) / cols,
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
                            for (final lr in today) _RecentLrRow(lr: lr),
                          ],
                        ),
                      );
                      final right = Column(
                        children: [
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                if (showMargin) ...[
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
                        children: [left, const SizedBox(height: 16), right],
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

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String sub;
  final bool compact;

  const _StatTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.sub,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return _compactTile();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(color: AppColors.slate, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Phones: a tiny tile so four fit in one row. The value auto-scales so long
  // money figures (e.g. ₹1,23,456) still fit the narrow width.
  Widget _compactTile() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.white,
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
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
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
              label,
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
        ],
      ),
    );
  }
}

class _RecentLrRow extends StatelessWidget {
  final LorryReceipt lr;
  const _RecentLrRow({required this.lr});

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
                  cleared ? 'Cleared' : inr(lr.freight.balance),
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
