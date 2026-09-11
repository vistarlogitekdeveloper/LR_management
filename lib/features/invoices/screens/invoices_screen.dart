import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/party.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../masters/providers/master_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/invoice_models.dart';
import '../providers/invoice_providers.dart';
import '../widgets/invoice_detail_dialog.dart';

/// The invoices landing screen: filter by customer, invoice-date range and
/// status, scan the headers, open one for the full document.
///
/// Issuing lives on `/invoices/new`; this screen only reads. The list comes
/// from `GET /invoices`, which returns HEADERS ONLY — no lines — so every row
/// here shows sub total / tax / total and nothing per-LR. The detail dialog
/// fetches the document.
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // UI gating only. The server enforces INVOICE_MANAGE on POST /invoices —
    // hiding the button is convenience, never the protection.
    final canManage = ref.watch(canManageInvoicesProvider);
    final filter = ref.watch(invoiceListFilterProvider);
    final invoicesAsync = ref.watch(invoiceListProvider);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final pad = mobile ? 14.0 : 28.0;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Invoices',
            subtitle: 'Tax invoices & billing',
            actions: [
              AppButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                kind: BtnKind.ghost,
                small: true,
                onPressed: () => ref.invalidate(invoiceListProvider),
              ),
              // Hidden rather than disabled: a user without the issue right
              // should not be shown a door they cannot open.
              if (canManage)
                AppButton(
                  label: 'New Invoice',
                  icon: Icons.add_rounded,
                  small: true,
                  onPressed: () => context.go('/invoices/new'),
                ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: const _FiltersCard(),
          ),
          Expanded(
            child: invoicesAsync.when(
              // A bare spinner would read the same as "nothing billed yet";
              // the skeleton says "rows are coming".
              loading: () => SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: const ShimmerCards(cards: 6),
              ),
              error: (e, _) => _ErrorState(
                message: friendlyErrorMessage(e),
                onRetry: () => ref.invalidate(invoiceListProvider),
              ),
              data: (invoices) => invoices.isEmpty
                  ? _EmptyState(
                      filtered: !filter.isEmpty,
                      canManage: canManage,
                      onClearFilters: () =>
                          ref.read(invoiceListFilterProvider.notifier).state =
                              const InvoiceListFilter(),
                      onNew: () => context.go('/invoices/new'),
                    )
                  : _InvoiceList(
                      invoices: invoices,
                      mobile: mobile,
                      padding: pad,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Customer / date-range / status filters. They live in
/// [invoiceListFilterProvider] rather than in screen state, so they survive a
/// navigation away and back.
class _FiltersCard extends ConsumerWidget {
  const _FiltersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(invoiceListFilterProvider);
    // Consignor parties, matching the create screen: an invoice's customer_id
    // is the LR's consignor_id server-side, so filtering by a customer-tagged
    // party that is not a consignor can only ever match nothing.
    final customers = ref.watch(consignorPartiesProvider);
    final selected = customers
        .where((p) => p.id == filter.customerId)
        .firstOrNull;
    // Locals so the null checks promote — the picker needs both bounds, and a
    // half-set range is not a range.
    final from = filter.from;
    final to = filter.to;
    final range = (from != null && to != null)
        ? DateTimeRange(start: from, end: to)
        : null;

    void setFilter(InvoiceListFilter next) =>
        ref.read(invoiceListFilterProvider.notifier).state = next;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: SearchableField<Party>(
              value: selected,
              options: customers,
              labelOf: (p) => p.name,
              subtitleOf: (p) => p.gst.isNotEmpty ? p.gst : p.city,
              hintText: 'All customers',
              dialogTitle: 'Customer',
              clearable: true,
              onChanged: (p) => setFilter(
                p == null
                    ? filter.copyWith(clearCustomer: true)
                    : filter.copyWith(customerId: p.id),
              ),
            ),
          ),
          _DateRangeChip(
            range: range,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: range,
                helpText: 'Filter by invoice date',
                saveText: 'Apply',
              );
              // The picker is a route of its own — this screen can be gone by
              // the time it closes, and touching ref then throws.
              if (picked == null || !context.mounted) return;
              setFilter(filter.copyWith(from: picked.start, to: picked.end));
            },
            onClear: () => setFilter(filter.copyWith(clearDates: true)),
          ),
          for (final option in _statusOptions)
            _FilterChip(
              label: option.$2,
              selected: filter.status == option.$1,
              onTap: () => setFilter(
                option.$1 == null
                    ? filter.copyWith(clearStatus: true)
                    : filter.copyWith(status: option.$1),
              ),
            ),
          if (!filter.isEmpty)
            AppButton(
              label: 'Clear',
              icon: Icons.filter_alt_off_outlined,
              kind: BtnKind.ghost,
              small: true,
              onPressed: () => setFilter(const InvoiceListFilter()),
            ),
        ],
      ),
    );
  }
}

/// (wire value, chip label) — null is "both statuses", which the repository
/// sends as no `status` param at all.
const _statusOptions = <(String?, String)>[
  (null, 'All'),
  (invoiceStatusIssued, 'Issued'),
  (invoiceStatusCancelled, 'Cancelled'),
];

class _InvoiceList extends StatelessWidget {
  const _InvoiceList({
    required this.invoices,
    required this.mobile,
    required this.padding,
  });

  final List<Invoice> invoices;
  final bool mobile;
  final double padding;

  @override
  Widget build(BuildContext context) {
    // Builder + separator: a year of billing is a long list, and only the
    // visible rows should ever be built.
    return ListView.separated(
      padding: EdgeInsets.all(padding),
      itemCount: invoices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final invoice = invoices[i];
        return _InvoiceRow(
          invoice: invoice,
          mobile: mobile,
          onTap: () => InvoiceDetailDialog.show(context, invoice.id),
        );
      },
    );
  }
}

/// One invoice header. A CANCELLED invoice is deliberately unmistakable —
/// struck-through number, muted text, a red-tinted card and a CANCELLED pill —
/// because reading a cancelled document as a live one is an accounting error,
/// not a cosmetic one.
class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.mobile,
    required this.onTap,
  });

  final Invoice invoice;
  final bool mobile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cancelled = invoice.isCancelled;
    final party = invoice.customerName.isNotEmpty
        ? invoice.customerName
        : (invoice.billToName.isNotEmpty ? invoice.billToName : '—');

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          invoice.number,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: cancelled ? AppColors.slate : AppColors.ink,
            decoration: cancelled ? TextDecoration.lineThrough : null,
            decorationColor: AppColors.danger,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatDate(invoice.invoiceDate),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.slate),
        ),
      ],
    );

    final customer = Text(
      party,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: cancelled ? AppColors.slate : AppColors.ink,
      ),
    );

    final amounts = <Widget>[
      _Amount(
        label: 'Taxable',
        value: inrPaise(invoice.subTotal),
        muted: cancelled,
      ),
      _Amount(
        label: 'Tax',
        value: inrPaise(invoice.taxAmount),
        muted: cancelled,
      ),
      _Amount(
        label: 'Total',
        value: inrPaise(invoice.total),
        strong: true,
        muted: cancelled,
      ),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cancelled
                ? AppColors.danger.withValues(alpha: 0.04)
                : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cancelled
                  ? AppColors.danger.withValues(alpha: 0.28)
                  : AppColors.line,
            ),
          ),
          child: mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: head),
                        const SizedBox(width: 8),
                        InvoiceStatusPill(status: invoice.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    customer,
                    const SizedBox(height: 10),
                    Wrap(spacing: 18, runSpacing: 8, children: amounts),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 4, child: head),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: customer),
                    const SizedBox(width: 12),
                    for (final amount in amounts) ...[
                      Expanded(flex: 3, child: amount),
                      const SizedBox(width: 12),
                    ],
                    InvoiceStatusPill(status: invoice.status),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.label,
    required this.value,
    this.strong = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.slate),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: strong ? 14.5 : 13.5,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
            color: muted
                ? AppColors.slate
                : (strong ? AppColors.plum : AppColors.ink),
          ),
        ),
      ],
    );
  }
}

/// Nothing to show — either the customer has never been billed, or the filters
/// exclude everything. Both get a way forward rather than a blank panel.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filtered,
    required this.canManage,
    required this.onClearFilters,
    required this.onNew,
  });

  final bool filtered;
  final bool canManage;
  final VoidCallback onClearFilters;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.plum.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 30,
                  color: AppColors.plum,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                filtered
                    ? 'No invoices match these filters'
                    : 'No invoices yet',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                filtered
                    ? 'Try a wider date range, another customer, or clear the '
                          'filters to see every invoice.'
                    : 'Pick a customer and a date range, tick the delivered '
                          'LRs to bill, and the invoice is numbered for you.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.slate),
              ),
              const SizedBox(height: 16),
              if (filtered)
                AppButton(
                  label: 'Clear filters',
                  icon: Icons.filter_alt_off_outlined,
                  kind: BtnKind.ghost,
                  onPressed: onClearFilters,
                )
              else if (canManage)
                AppButton(
                  label: 'New Invoice',
                  icon: Icons.add_rounded,
                  onPressed: onNew,
                ),
            ],
          ),
        ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Could not load invoices',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.slate),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill that opens the invoice-date range picker; shows the range and a
/// clear (×) once one is set. Matches the Accounts filter bar.
class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({
    required this.range,
    required this.onTap,
    required this.onClear,
  });

  final DateTimeRange? range;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final r = range;
    final active = r != null;
    final label = active
        ? '${formatDate(r.start)} – ${formatDate(r.end)}'
        : 'Invoice date';
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
            border: Border.all(color: active ? AppColors.plum : AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range_rounded,
                size: 15,
                color: active ? AppColors.white : AppColors.slate,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.white : AppColors.ink,
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
                      color: AppColors.white,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
      ),
    );
  }
}
