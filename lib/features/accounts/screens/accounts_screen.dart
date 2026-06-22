import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../admin/providers/audit_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lr/providers/lr_providers.dart';
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

final _accountsFilterProvider =
    StateProvider<_PayFilter>((ref) => _PayFilter.all);

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(lrListProvider);
    final filter = ref.watch(_accountsFilterProvider);

    final sorted = [...lrs]..sort((a, b) => b.date.compareTo(a.date));
    final filtered = sorted.where((lr) {
      switch (filter) {
        case _PayFilter.all:
          return true;
        case _PayFilter.awaitingAdvance:
          return lr.freight.advance <= 0 && lr.freight.total > 0;
        case _PayFilter.awaitingBalance:
          return lr.freight.advance > 0 && lr.freight.balance > 0;
        case _PayFilter.paid:
          return lr.freight.total > 0 && lr.freight.balance <= 0;
      }
    }).toList();

    final totalAdvance =
        lrs.fold<double>(0, (s, l) => s + l.freight.advance);
    final totalPending =
        lrs.fold<double>(0, (s, l) => s + l.freight.balance);

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
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 700 ? 2 : 1;
                      final tiles = <Widget>[
                        _MiniTile(
                          label: 'Advance Received',
                          value: inr(totalAdvance),
                          icon: Icons.savings_outlined,
                          color: AppColors.ok,
                        ),
                        _MiniTile(
                          label: 'Pending Balance',
                          value: inr(totalPending),
                          icon: Icons.pending_actions_outlined,
                          color: AppColors.red,
                        ),
                      ];
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final t in tiles)
                            SizedBox(
                              width:
                                  (c.maxWidth - 16 * (cols - 1)) / cols,
                              child: t,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.receipt_long_outlined,
                          title: 'LR Payments',
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in _PayFilter.values)
                              _FilterChip(
                                label: f.label,
                                selected: filter == f,
                                onTap: () => ref
                                    .read(_accountsFilterProvider.notifier)
                                    .state = f,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'No LRs in this view',
                                style: TextStyle(
                                  color: AppColors.slate
                                      .withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (final lr in filtered)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _LrPaymentCard(lr: lr),
                                ),
                            ],
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
}

class _LrPaymentCard extends ConsumerWidget {
  final LorryReceipt lr;
  const _LrPaymentCard({required this.lr});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAdvance = lr.freight.advance > 0;
    final hasBalance = lr.freight.balance > 0;
    final fullyPaid = lr.freight.total > 0 && !hasBalance;

    return Container(
      padding: const EdgeInsets.all(16),
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
              Row(
                children: [
                  Text(
                    lr.number,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusPill(status: lr.status),
                  const SizedBox(width: 6),
                  if (fullyPaid)
                    const _BadgePill(
                      text: 'Paid',
                      fg: AppColors.ok,
                    )
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
                style: const TextStyle(
                  color: AppColors.slate,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              Text(
                '${formatDate(lr.date)} · ${lr.route}',
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                ),
              ),
            ],
          );

          final amounts = Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Amount(label: 'Total', value: lr.freight.total),
              _Amount(
                label: 'Advance',
                value: lr.freight.advance,
                color: AppColors.ok,
              ),
              _Amount(
                label: 'Remaining',
                value: lr.freight.balance,
                color: hasBalance ? AppColors.red : AppColors.ok,
                emphasis: true,
              ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (!hasAdvance && lr.freight.total > 0)
                AppButton(
                  label: 'Pay Advance',
                  kind: BtnKind.soft,
                  icon: Icons.savings_outlined,
                  small: true,
                  onPressed: () => _payAdvance(context, ref),
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
                const _BadgePill(
                  text: 'Settled',
                  fg: AppColors.ok,
                ),
            ],
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: header),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: amounts),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: actions),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              amounts,
              const SizedBox(height: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  Future<void> _payAdvance(BuildContext context, WidgetRef ref) async {
    final amount = await _showAmountDialog(
      context: context,
      title: 'Pay Advance · ${lr.number}',
      message:
          'Outstanding ${inr(lr.freight.balance)} of ${inr(lr.freight.total)}.',
      max: lr.freight.balance,
      confirmLabel: 'Record Advance',
    );
    if (amount == null || amount <= 0) return;
    final newAdvance = lr.freight.advance + amount;
    final newFreight = lr.freight.copyWith(advance: newAdvance);
    final balance = newFreight.balance;
    final updated = lr.copyWith(
      freight: newFreight,
      payType: balance <= 0 ? PayType.paid : lr.payType,
    );
    ref.read(lrListProvider.notifier).update(updated);
    final user = ref.read(currentUserProvider);
    ref.read(auditProvider.notifier).log(
          user: user?.username ?? 'accounts',
          action: 'PAYMENT',
          entity: 'LR',
          entityRef: lr.number,
          details: 'Advance received ${inr(amount)}',
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Advance ${inr(amount)} recorded for ${lr.number}')),
    );
  }

  Future<void> _completePayment(BuildContext context, WidgetRef ref) async {
    final remaining = lr.freight.balance;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Complete payment for ${lr.number}?'),
            content: Text(
              'Remaining balance ${inr(remaining)} will be marked as received. '
              'Total ${inr(lr.freight.total)} − Advance ${inr(lr.freight.advance)} = ${inr(remaining)}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark Paid'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final newFreight = lr.freight.copyWith(advance: lr.freight.total);
    final updated = lr.copyWith(
      freight: newFreight,
      payType: PayType.paid,
    );
    ref.read(lrListProvider.notifier).update(updated);
    final user = ref.read(currentUserProvider);
    ref.read(auditProvider.notifier).log(
          user: user?.username ?? 'accounts',
          action: 'PAYMENT',
          entity: 'LR',
          entityRef: lr.number,
          details: 'Balance ${inr(remaining)} settled · marked Paid',
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${lr.number} settled in full')),
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
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

  const _Amount({
    required this.label,
    required this.value,
    this.color,
    this.emphasis = false,
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
          inr(value),
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

  const _MiniTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.3,
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
