import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/section_title.dart';
import '../data/invoice_models.dart';

/// The tickable list of LRs a customer may be billed for.
///
/// Every row comes straight from `GET /invoices/billable-lrs`, which has
/// ALREADY excluded everything that may not be billed — anything not DELIVERED,
/// anything stamped with a bill number, and anything sitting on a live invoice.
/// Nothing is re-filtered here, and the empty state spells that rule out,
/// because "why is my LR not in the list?" is the question Accounts otherwise
/// asks every single time.
class BillableLrTable extends StatelessWidget {
  const BillableLrTable({
    super.key,
    required this.rows,
    required this.selected,
    required this.hasCustomer,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onRetry,
    this.pending = false,
    this.selectionError,
  });

  /// The billable set for the current customer + period.
  final AsyncValue<List<BillableLr>> rows;

  /// Ticked LR ids, owned by `billableSelectionProvider`.
  final Set<String> selected;

  /// False until a customer is picked — the server requires one, so the
  /// provider resolves to an empty list without asking.
  final bool hasCustomer;

  final ValueChanged<String> onToggle;
  final void Function(Iterable<String> ids) onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onRetry;

  /// True while the screen is holding a debounced customer/period change that
  /// has not reached the provider yet. The rows on screen belong to the PREVIOUS
  /// query in that window, so the skeleton stands in for them rather than
  /// letting a stale empty state read as an answer.
  final bool pending;

  /// Validation message from a failed issue ("select at least one LR").
  final String? selectionError;

  @override
  Widget build(BuildContext context) {
    final body = pending
        ? const ShimmerRows(rows: 6)
        : switch (rows) {
            AsyncData(:final value) =>
              value.isEmpty
                  ? _EmptyState(hasCustomer: hasCustomer)
                  : _RowsView(
                      rows: value,
                      selected: selected,
                      onToggle: onToggle,
                    ),
            AsyncError(:final error) => _ErrorState(
              message: friendlyErrorMessage(error),
              onRetry: onRetry,
            ),
            // Includes the refresh after an ALREADY_INVOICED clash, which arrives as
            // AsyncLoading carrying the previous rows — showing the skeleton there is
            // deliberate: those rows are known to be stale.
            _ => const ShimmerRows(rows: 6),
          };

    // While a change is pending, the select-all control and the footer would be
    // counting the previous query's rows — hide them with the same stroke.
    final data = pending
        ? const <BillableLr>[]
        : (rows.valueOrNull ?? const <BillableLr>[]);
    final picked = data.where((lr) => selected.contains(lr.id)).toList();
    final allPicked = data.isNotEmpty && picked.length == data.length;
    final error = selectionError;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            icon: Icons.fact_check_outlined,
            title: 'Billable LRs',
            trailing: data.isEmpty
                ? null
                : AppButton(
                    label: allPicked ? 'Clear' : 'Select all (${data.length})',
                    icon: allPicked
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    kind: BtnKind.soft,
                    small: true,
                    onPressed: allPicked
                        ? onClearSelection
                        : () => onSelectAll(data.map((lr) => lr.id)),
                  ),
          ),
          body,
          if (data.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SelectionFooter(total: data.length, picked: picked),
          ],
          if (error != null && error.isNotEmpty)
            _SelectionError(message: error),
        ],
      ),
    );
  }
}

/// Rows on wide viewports, stacked cards on phones. One shared layout class
/// keeps the header and the rows on identical column geometry.
class _RowsView extends StatelessWidget {
  const _RowsView({
    required this.rows,
    required this.selected,
    required this.onToggle,
  });

  final List<BillableLr> rows;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              for (final lr in rows)
                _LrCard(
                  lr: lr,
                  selected: selected.contains(lr.id),
                  onTap: () => onToggle(lr.id),
                ),
            ],
          );
        }
        return Column(
          children: [
            const _HeaderRow(),
            for (final lr in rows)
              _LrRow(
                lr: lr,
                selected: selected.contains(lr.id),
                onTap: () => onToggle(lr.id),
              ),
          ],
        );
      },
    );
  }
}

/// The column geometry, in one place, so a header cell can never drift away
/// from the data cell beneath it.
class _RowLayout extends StatelessWidget {
  const _RowLayout({
    required this.leading,
    required this.number,
    required this.date,
    required this.vehicle,
    required this.route,
    required this.mode,
    required this.amount,
  });

  final Widget leading;
  final Widget number;
  final Widget date;
  final Widget vehicle;
  final Widget route;
  final Widget mode;
  final Widget amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 40, child: leading),
        Expanded(flex: 26, child: number),
        const SizedBox(width: 10),
        SizedBox(width: 100, child: date),
        Expanded(flex: 20, child: vehicle),
        Expanded(flex: 28, child: route),
        SizedBox(width: 84, child: mode),
        SizedBox(width: 108, child: amount),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  static const _style = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    color: AppColors.slate,
    letterSpacing: 0.3,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: const _RowLayout(
        leading: SizedBox.shrink(),
        number: Text('LR NUMBER', style: _style),
        date: Text('DATE', style: _style),
        vehicle: Text('VEHICLE', style: _style),
        route: Text('ROUTE', style: _style),
        mode: Text('MODE', style: _style),
        amount: Text('AMOUNT', style: _style, textAlign: TextAlign.right),
      ),
    );
  }
}

class _LrRow extends StatelessWidget {
  const _LrRow({required this.lr, required this.selected, required this.onTap});

  final BillableLr lr;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.plum.withValues(alpha: 0.05)
          : AppColors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: _RowLayout(
            leading: Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              activeColor: AppColors.plum,
              onChanged: (_) => onTap(),
              semanticLabel: 'Bill LR ${lr.number}',
            ),
            number: Text(
              lr.number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            date: Text(formatDate(lr.lrDate), style: _cellStyle),
            vehicle: Text(
              lr.vehicleNo.isEmpty ? '—' : lr.vehicleNo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _cellStyle,
            ),
            route: Text(
              lr.route.isEmpty ? '—' : lr.route,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _cellStyle,
            ),
            mode: lr.mode.isEmpty
                ? const Text('—', style: _cellStyle)
                : _ModeChip(mode: lr.mode),
            amount: Text(
              lr.hasAmount ? inrPaise(lr.billedAmount!) : '—',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _cellStyle = TextStyle(
  fontSize: 12.5,
  color: AppColors.slate,
  fontWeight: FontWeight.w600,
);

/// Phone layout: the same row, stacked, with a 48 px tap target.
class _LrCard extends StatelessWidget {
  const _LrCard({
    required this.lr,
    required this.selected,
    required this.onTap,
  });

  final BillableLr lr;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      formatDate(lr.lrDate),
      if (lr.vehicleNo.isNotEmpty) lr.vehicleNo,
      if (lr.route.isNotEmpty) lr.route,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.plum.withValues(alpha: 0.05)
            : AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.plum : AppColors.line,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  activeColor: AppColors.plum,
                  onChanged: (_) => onTap(),
                  semanticLabel: 'Bill LR ${lr.number}',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lr.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(details, style: _cellStyle),
                      if (lr.mode.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _ModeChip(mode: lr.mode),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    lr.hasAmount ? inrPaise(lr.billedAmount!) : '—',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
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

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          mode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.orange,
          ),
        ),
      ),
    );
  }
}

/// "N of M selected" with the running total — the figure Accounts reconciles
/// against before issuing.
class _SelectionFooter extends StatelessWidget {
  const _SelectionFooter({required this.total, required this.picked});

  final int total;
  final List<BillableLr> picked;

  @override
  Widget build(BuildContext context) {
    final sum = picked.fold<double>(
      0,
      (acc, lr) => acc + (lr.billedAmount ?? 0),
    );
    // A withheld amount arrives as null, not 0: the server releases
    // billed_amount only to a holder of all three rate permissions. Testing for
    // null rather than a zero sum matters in both directions — a genuinely
    // zero-value LR is not "hidden", and one withheld row among priced ones is.
    final hidden = picked.any((lr) => !lr.hasAmount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${picked.length} of $total selected',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                inrPaise(sum),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.plum,
                ),
              ),
            ],
          ),
          if (hidden) ...[
            const SizedBox(height: 6),
            const Text(
              'Every selected LR shows ₹0. If that looks wrong, your account '
              'cannot see rate figures — the server still prices the invoice.',
              style: TextStyle(fontSize: 11.5, color: AppColors.slate),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionError extends StatelessWidget {
  const _SelectionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: AppColors.red,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two empty states, because they are two different questions: "what do I do
/// next?" before a customer is picked, and "where are my LRs?" after.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasCustomer});

  final bool hasCustomer;

  @override
  Widget build(BuildContext context) {
    final title = hasCustomer
        ? 'No billable LRs in this period'
        : 'Pick a customer to start';
    final message = hasCustomer
        ? 'Only DELIVERED LRs that have not been billed yet appear here. An LR '
              'already on a live invoice, or one already stamped with a bill '
              'number, is deliberately excluded — cancel the invoice holding it '
              'to release it. Widening the date range is usually what is needed.'
        : 'Choose the customer to bill, then narrow the period if you want. '
              'Their delivered, not-yet-billed LRs will be listed here to tick.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.plum.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              hasCustomer ? Icons.inbox_outlined : Icons.person_search_outlined,
              color: AppColors.plum,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.slate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.danger,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Could not load the billable LRs',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.slate,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            kind: BtnKind.ghost,
            small: true,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
