import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
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

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(lrListProvider);
    final filter = ref.watch(_accountsFilterProvider);

    final sorted = [...lrs]..sort((a, b) => b.date.compareTo(a.date));
    // Accounts pays the transporter, so payment state is tracked against the
    // transporter freight (90% advance / 10% against POD), not the customer
    // total. `balance` here means the transporter freight still unpaid.
    final filtered = sorted.where((lr) {
      final freight = lr.freight.freight;
      final balance = freight - lr.freight.advance;
      switch (filter) {
        case _PayFilter.all:
          return true;
        case _PayFilter.awaitingAdvance:
          return lr.freight.advance <= 0 && freight > 0;
        case _PayFilter.awaitingBalance:
          return lr.freight.advance > 0 && balance > 0.01;
        case _PayFilter.paid:
          return freight > 0 && balance <= 0.01;
      }
    }).toList();

    final totalAdvance = lrs.fold<double>(0, (s, l) => s + l.freight.advance);
    final totalPending = lrs.fold<double>(0, (s, l) {
      final pend = l.freight.freight - l.freight.advance;
      return s + (pend > 0 ? pend : 0);
    });

    final isMobile = MediaQuery.of(context).size.width < 600;

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
                      // Two compact tiles per row on phones, full grid otherwise.
                      final cols = c.maxWidth >= 700
                          ? 2
                          : mobile
                          ? 2
                          : 1;
                      final gap = mobile ? 10.0 : 16.0;
                      final tiles = <Widget>[
                        _MiniTile(
                          label: 'Advance Received',
                          value: inr(totalAdvance),
                          icon: Icons.savings_outlined,
                          color: AppColors.ok,
                          compact: mobile,
                        ),
                        _MiniTile(
                          label: 'Pending Balance',
                          value: inr(totalPending),
                          icon: Icons.pending_actions_outlined,
                          color: AppColors.red,
                          compact: mobile,
                        ),
                      ];
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final t in tiles)
                            SizedBox(
                              width: (c.maxWidth - gap * (cols - 1)) / cols,
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
                                onTap: () =>
                                    ref
                                            .read(
                                              _accountsFilterProvider.notifier,
                                            )
                                            .state =
                                        f,
                              ),
                          ],
                        ),
                        SizedBox(height: isMobile ? 12 : 16),
                        if (filtered.isEmpty)
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
                          Column(
                            children: [
                              for (final lr in filtered)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: isMobile ? 8 : 12,
                                  ),
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
    // Payment state is tracked against the transporter freight (the amount
    // Accounts pays out): 90% advance up front, the ~10% balance against POD.
    final freight = lr.freight.freight;
    final advance = lr.freight.advance;
    final transBalance = (freight - advance) > 0 ? (freight - advance) : 0.0;
    final hasAdvance = advance > 0;
    final hasBalance = transBalance > 0.01;
    final fullyPaid = freight > 0 && !hasBalance;
    // Resolve the full transporter (with bank details) from the masters list so
    // accounts can pay the correct party.
    final transporter = ref
        .watch(transportersProvider)
        .where((t) => t.id == lr.transporter.id)
        .firstOrNull;

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
              _Amount(label: 'Transporter Freight', value: freight),
              _Amount(
                label: 'Advance',
                value: advance,
                color: AppColors.ok,
              ),
              _Amount(
                label: 'Balance (after POD)',
                value: transBalance,
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
              _advancePlan(context),
              _billingMisInfo(context),
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

  /// The 90/10 transporter advance plan: 90% of the transporter freight is
  /// released up front, the remaining 10% settles after POD. The actual figures
  /// are computed on `freight` (the transporter freight, excluding the
  /// customer-side door/handling charges) — the same base Accounts pays out on.
  Widget _advancePlan(BuildContext context) {
    final freight = lr.freight.freight;
    if (freight <= 0) return const SizedBox.shrink();
    final advance = freight * 0.9; // 90% up front
    final afterPod = freight - advance; // 10% against POD
    // Treat the advance as released once the recorded advance covers the 90%
    // target (small epsilon for rounding to whole rupees).
    final advanceDone = lr.freight.advance + 0.5 >= advance;
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
                text: advanceDone ? 'Advance Paid' : 'Advance Due',
                fg: advanceDone ? AppColors.ok : AppColors.orange,
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
                label: 'Advance 90% (now)',
                value: advance,
                color: AppColors.ok,
                emphasis: true,
              ),
              _Amount(
                label: 'Balance 10% (after POD)',
                value: afterPod,
                color: AppColors.slate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Read-only summary of the accounts-owned billing / MIS fields, shown only
  /// in the Accounts view. Empty (hidden) until Accounts fills them in.
  Widget _billingMisInfo(BuildContext context) {
    final chips = <Widget>[];
    if (lr.vistarBillNo.isNotEmpty) chips.add(_kvChip('Bill No', lr.vistarBillNo));
    if (lr.vistarBillDate != null) {
      chips.add(_kvChip('Bill Date', formatDate(lr.vistarBillDate!)));
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

  /// Releases the standard 90% transporter advance and triggers the
  /// advance-paid notification email (LR creator + admins + master admin). The
  /// backend computes the amount from the transporter freight.
  Future<void> _markAdvancePaid(BuildContext context, WidgetRef ref) async {
    final freight = lr.freight.freight;
    final advance = freight * 0.9;
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
              'Release ${inr(advance)} (90% of the transporter freight ${inr(freight)}) '
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
        SnackBar(content: Text('Could not mark advance paid: $e')),
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
      ).showSnackBar(SnackBar(content: Text('Could not record advance: $e')));
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
        SnackBar(content: Text('Could not complete payment: $e')),
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
      'vistar_bill_no': billNoCtrl.text.trim(),
      'vistar_bill_date': dateOnly(billDate),
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
        SnackBar(content: Text('Could not save billing details: $e')),
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
