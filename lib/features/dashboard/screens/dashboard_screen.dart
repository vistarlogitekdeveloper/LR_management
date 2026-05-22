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
import '../../shell/widgets/app_topbar.dart';
import '../models/role_flow.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final lrs = ref.watch(lrListProvider);

    final flow = user == null ? null : RoleFlows.flows[user.role];
    final canCreate = user?.role.canCreate ?? false;

    final today = lrs.take(6).toList();
    final pendingFreight = lrs
        .where((lr) => lr.freight.balance > 0)
        .fold<double>(0, (sum, lr) => sum + lr.freight.balance);
    final inTransit =
        lrs.where((lr) => lr.status == LrStatus.inTransit).length;
    final dispatched =
        lrs.where((lr) => lr.status != LrStatus.booked).length;
    final marginMtd =
        lrs.fold<double>(0, (sum, lr) => sum + lr.freight.vistarMargin);

    final customerTotals = <String, double>{};
    for (final lr in lrs) {
      final key = lr.consignor.name;
      customerTotals[key] =
          (customerTotals[key] ?? 0) + lr.freight.total;
    }
    final topCustomers = customerTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFour = topCustomers.take(4).toList();
    final maxCust =
        topFour.isEmpty ? 1.0 : topFour.first.value;

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
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (flow != null) ...[
                    _RoleFlowStrip(flow: flow),
                    const SizedBox(height: 20),
                  ],
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 1100
                          ? 4
                          : c.maxWidth >= 700
                              ? 2
                              : 1;
                      final stats = <_StatTile>[
                        _StatTile(
                          icon: Icons.description_outlined,
                          tint: AppColors.plum,
                          label: 'Today\'s LR',
                          value: '${today.length}',
                          sub: '${lrs.length} total in system',
                        ),
                        _StatTile(
                          icon: Icons.local_shipping_outlined,
                          tint: AppColors.orange,
                          label: 'Vehicles Dispatched',
                          value: '$dispatched',
                          sub: '$inTransit in transit',
                        ),
                        _StatTile(
                          icon: Icons.schedule_rounded,
                          tint: AppColors.amber,
                          label: 'Pending Delivery',
                          value: '$inTransit',
                          sub: 'On the road',
                        ),
                        _StatTile(
                          icon: Icons.account_balance_wallet_outlined,
                          tint: AppColors.red,
                          label: 'Pending Freight',
                          value: inr(pendingFreight),
                          sub: 'across open LRs',
                        ),
                      ];
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final s in stats)
                            SizedBox(
                              width: (c.maxWidth - 16 * (cols - 1)) / cols,
                              child: s,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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
                                const SizedBox(height: 16),
                                _MarginCard(
                                  margin: marginMtd,
                                  consignments: lrs.length,
                                ),
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
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < flow.steps.length; i++) ...[
                    _FlowStepCard(
                      step: flow.steps[i],
                      index: i + 1,
                    ),
                    if (i < flow.steps.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.line,
                          size: 22,
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
  const _FlowStepCard({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.go(step.path),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
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
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String sub;

  const _StatTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _RecentLrRow extends StatelessWidget {
  final LorryReceipt lr;
  const _RecentLrRow({required this.lr});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.go('/lrs/${lr.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.plum.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.description_outlined,
                  size: 18, color: AppColors.plum),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lr.number,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    '${lr.consignor.name}  →  ${lr.consignee.name}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatDate(lr.date),
              style:
                  const TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
            const SizedBox(width: 16),
            StatusPill(status: lr.status),
            const SizedBox(width: 10),
            Text(
              lr.freight.balance > 0
                  ? inr(lr.freight.balance)
                  : 'Cleared',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: lr.freight.balance > 0
                    ? AppColors.red
                    : AppColors.ok,
                fontSize: 12.5,
              ),
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
  const _TopCustomerRow(
      {required this.name, required this.value, required this.max});

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
