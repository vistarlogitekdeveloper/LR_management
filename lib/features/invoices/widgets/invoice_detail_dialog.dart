import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../reports/services/export_service.dart';
import '../data/invoice_models.dart';
import '../providers/invoice_providers.dart';

/// Read-only view of one issued invoice: the parties, the printed lines with
/// the LRs behind each of them, and the totals — everything Accounts checks
/// before the PDF goes out.
///
/// Nothing here is editable: an issued invoice is a legal document the server
/// owns. The only two actions are downloading the rendered PDF and cancelling,
/// which releases its LRs back into the billable pool.
class InvoiceDetailDialog extends ConsumerStatefulWidget {
  const InvoiceDetailDialog({super.key, required this.invoiceId});

  final String invoiceId;

  static Future<void> show(BuildContext context, String invoiceId) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
          child: InvoiceDetailDialog(invoiceId: invoiceId),
        ),
      ),
    );
  }

  @override
  ConsumerState<InvoiceDetailDialog> createState() =>
      _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends ConsumerState<InvoiceDetailDialog> {
  // Both actions disable the whole footer while they run: the PDF render is
  // slow enough to invite a second tap, and cancelling twice would put a
  // confusing 409 in front of the operator.
  bool _downloading = false;
  bool _cancelling = false;

  Future<void> _download(Invoice invoice) async {
    if (_downloading || _cancelling) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(invoiceRepositoryProvider)
          .pdfBytes(invoice.id);
      await ExportService.shareBytes(bytes, _pdfFilename(invoice.number));
      if (!mounted) return;
      setState(() => _downloading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  Future<void> _cancel(Invoice invoice) async {
    if (_downloading || _cancelling) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Cancel invoice ${invoice.number}?',
      message:
          'The invoice stays on record, marked CANCELLED, and the '
          '${invoice.lrCount} LR(s) it bills are released back into the '
          'billable pool — anyone may invoice them again. This cannot be '
          'undone.',
      confirmLabel: 'Cancel Invoice',
    );
    if (!confirmed || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(invoiceRepositoryProvider).cancel(invoice.id);
      if (!mounted) return;
      // Refetch this document (it now reads CANCELLED) and the list behind it.
      ref.invalidate(invoiceDetailProvider(invoice.id));
      ref.invalidate(invoiceListProvider);
      setState(() => _cancelling = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Invoice ${invoice.number} cancelled')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final canManage = ref.watch(canManageInvoicesProvider);
    // Header and footer render from whatever has already arrived; the body
    // owns the loading / error / content switch.
    final invoice = async.valueOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          invoice: invoice,
          busy: _downloading || _cancelling,
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: async.when(
            loading: () => const SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: ShimmerCards(cards: 4, height: 92),
            ),
            error: (e, _) => _ErrorBody(
              message: friendlyErrorMessage(e),
              onRetry: () =>
                  ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
            ),
            data: (inv) => _Body(invoice: inv),
          ),
        ),
        _Footer(
          invoice: invoice,
          canManage: canManage,
          downloading: _downloading,
          cancelling: _cancelling,
          onDownload: _download,
          onCancel: _cancel,
          onClose: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// An invoice number is full of '/' (VL/INV/26-27/00123) and a slash is not a
/// legal filename character on any platform this ships to — nor are the rest
/// of the Windows-reserved set, so all of them collapse to '-'.
final _unsafeFilenameChars = RegExp(r'[\\/:*?"<>|\s]+');

String _pdfFilename(String number) {
  final safe = number.replaceAll(_unsafeFilenameChars, '-');
  return 'invoice_${safe.isEmpty ? 'document' : safe}.pdf';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.invoice,
    required this.busy,
    required this.onClose,
  });

  final Invoice? invoice;
  final bool busy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  inv == null
                      ? 'Invoice'
                      : (inv.isTaxInvoice ? 'Tax Invoice' : 'Invoice'),
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
                const SizedBox(height: 2),
                Text(
                  inv?.number ?? '…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                if (inv != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatDate(inv.invoiceDate),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.slate,
                        ),
                      ),
                      InvoiceStatusPill(status: inv.status),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: busy ? null : onClose,
            icon: const Icon(Icons.close_rounded, color: AppColors.slate),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final billTo = _PartyBlock(
      title: 'Bill To',
      name: invoice.billToName,
      address: invoice.billToAddress,
      gstin: invoice.billToGstin,
      state: invoice.billToState,
      stateCode: invoice.billToStateCode,
    );
    final shipTo = _PartyBlock(
      title: 'Ship To',
      name: invoice.shipToName,
      address: invoice.shipToAddress,
      gstin: invoice.shipToGstin,
      state: invoice.shipToState,
      stateCode: invoice.shipToStateCode,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The dialog is narrower than the window, so the split has to follow
          // the CARD's width, not the screen's.
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 620
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: billTo),
                      const SizedBox(width: 12),
                      Expanded(child: shipTo),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [billTo, const SizedBox(height: 12), shipTo],
                  ),
          ),
          const SizedBox(height: 16),
          _MetaGrid(invoice: invoice),
          const SizedBox(height: 18),
          const _SectionLabel('Items'),
          const SizedBox(height: 8),
          for (final line in invoice.lines) ...[
            _LineBlock(line: line),
            const SizedBox(height: 10),
          ],
          if (invoice.lines.isEmpty)
            const Text(
              'This invoice has no printed lines.',
              style: TextStyle(fontSize: 13, color: AppColors.slate),
            ),
          const SizedBox(height: 8),
          _Totals(invoice: invoice),
          if (invoice.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionLabel('Notes'),
            const SizedBox(height: 6),
            Text(
              invoice.notes,
              style: const TextStyle(fontSize: 13, color: AppColors.ink),
            ),
          ],
        ],
      ),
    );
  }
}

class _PartyBlock extends StatelessWidget {
  const _PartyBlock({
    required this.title,
    required this.name,
    required this.address,
    required this.gstin,
    required this.state,
    required this.stateCode,
  });

  final String title;
  final String name;
  final String address;
  final String gstin;
  final String state;
  final String stateCode;

  @override
  Widget build(BuildContext context) {
    final stateLine = [
      if (state.isNotEmpty) state,
      if (stateCode.isNotEmpty) 'Code $stateCode',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.slate,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name.isEmpty ? '—' : name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              address,
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
            ),
          ],
          if (gstin.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'GSTIN  $gstin',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
          if (stateLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              stateLine,
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
            ),
          ],
        ],
      ),
    );
  }
}

/// Place of supply, references and the rest of the header fields. Empty ones
/// are dropped rather than shown as '—', so the block stays scannable.
class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final due = invoice.dueDate;
    final placeOfSupply = [
      if (invoice.placeOfSupply.isNotEmpty) invoice.placeOfSupply,
      if (invoice.placeOfSupplyCode.isNotEmpty) invoice.placeOfSupplyCode,
    ].join(' · ');
    final region = [
      if (invoice.regionName.isNotEmpty) invoice.regionName,
      if (invoice.regionCode.isNotEmpty) invoice.regionCode,
    ].join(' · ');

    final entries = <(String, String)>[
      ('Invoice date', formatDate(invoice.invoiceDate)),
      if (due != null) ('Due date', formatDate(due)),
      if (placeOfSupply.isNotEmpty) ('Place of supply', placeOfSupply),
      if (invoice.vendorCode.isNotEmpty) ('Vendor code', invoice.vendorCode),
      if (invoice.referenceNo.isNotEmpty) ('Reference no', invoice.referenceNo),
      if (invoice.otherReference.isNotEmpty)
        ('Other reference', invoice.otherReference),
      if (invoice.hsnSac.isNotEmpty) ('HSN / SAC', invoice.hsnSac),
      if (invoice.serviceMode.isNotEmpty) ('Service mode', invoice.serviceMode),
      if (region.isNotEmpty) ('Region', region),
      ('LRs billed', '${invoice.lrCount}'),
    ];

    return Wrap(
      spacing: 22,
      runSpacing: 12,
      children: [
        for (final entry in entries)
          SizedBox(width: 170, child: _KeyValue(entry.$1, entry.$2)),
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.slate),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// One printed line and, under it, every LR that makes it up — the part
/// Accounts actually verifies against the customer's own records.
class _LineBlock extends StatelessWidget {
  const _LineBlock({required this.line});

  final InvoiceLine line;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (line.hsnSac.isNotEmpty) 'HSN/SAC ${line.hsnSac}',
      '${line.qtyText}${line.uom.isEmpty ? '' : ' ${line.uom}'}'
          ' × ${inrPaise(line.rate)}',
    ].join('   ·   ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.srNo > 0
                      ? '${line.srNo}.  ${line.title}'
                      : (line.title.isEmpty ? 'Line' : line.title),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                inrPaise(line.amount),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
          if (line.lrs.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 8),
            for (final lr in line.lrs) _LrRow(lr: lr),
          ],
        ],
      ),
    );
  }
}

class _LrRow extends StatelessWidget {
  const _LrRow({required this.lr});

  final InvoiceLineLr lr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 8),
            child: Icon(Icons.circle, size: 6, color: AppColors.plumLight),
          ),
          Expanded(
            child: Text(
              lr.description.isEmpty ? lr.lrNumber : lr.description,
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            inrPaise(lr.amount),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.slate,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sub total, the tax heads this invoice actually carries, the grand total and
/// the words. Every figure is READ from the stored document — nothing here is
/// recomputed, so a later GST-rate change can never restate an old invoice.
class _Totals extends StatelessWidget {
  const _Totals({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    // (heading, amount) per tax head — INTRA prints CGST + SGST, INTER prints
    // IGST, NONE prints neither. Rates come from the stored columns, so the
    // heading always matches what the customer's copy says.
    final taxRows = <(String, double)>[
      if (invoice.taxMode == invoiceTaxModeIntra) ...[
        ('CGST ${pctText(invoice.cgstRate ?? 0)}%', invoice.cgstAmount ?? 0),
        ('SGST ${pctText(invoice.sgstRate ?? 0)}%', invoice.sgstAmount ?? 0),
      ] else if (invoice.taxMode == invoiceTaxModeInter)
        ('IGST ${pctText(invoice.igstRate ?? 0)}%', invoice.igstAmount ?? 0),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.plum.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TotalRow(label: 'Sub total', value: inrPaise(invoice.subTotal)),
          for (final row in taxRows)
            _TotalRow(label: row.$1, value: inrPaise(row.$2)),
          if (taxRows.isEmpty)
            _TotalRow(label: invoice.taxLabel, value: inrPaise(0)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.line),
          ),
          _TotalRow(
            label: 'Total',
            value: inrPaise(invoice.total),
            strong: true,
          ),
          if (invoice.amountInWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              invoice.amountInWords,
              style: const TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppColors.slate,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 14 : 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: strong ? AppColors.ink : AppColors.slate,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 16 : 13,
              fontWeight: FontWeight.w800,
              color: strong ? AppColors.plum : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppColors.slate,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.danger),
          const SizedBox(height: 10),
          const Text(
            'Could not load this invoice',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
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
          const SizedBox(height: 14),
          AppButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.invoice,
    required this.canManage,
    required this.downloading,
    required this.cancelling,
    required this.onDownload,
    required this.onCancel,
    required this.onClose,
  });

  final Invoice? invoice;
  final bool canManage;
  final bool downloading;
  final bool cancelling;
  final ValueChanged<Invoice> onDownload;
  final ValueChanged<Invoice> onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final busy = downloading || cancelling;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 8,
        children: [
          AppButton(
            label: 'Close',
            kind: BtnKind.ghost,
            onPressed: busy ? null : onClose,
          ),
          if (inv != null)
            AppButton(
              label: 'Download PDF',
              icon: Icons.picture_as_pdf_outlined,
              kind: BtnKind.soft,
              loading: downloading,
              onPressed: cancelling ? null : () => onDownload(inv),
            ),
          // Cancelling is a write, and a cancelled invoice cannot be cancelled
          // again — the server would refuse it anyway.
          if (inv != null && canManage && !inv.isCancelled)
            AppButton(
              label: 'Cancel Invoice',
              icon: Icons.block_rounded,
              kind: BtnKind.danger,
              loading: cancelling,
              onPressed: downloading ? null : () => onCancel(inv),
            ),
        ],
      ),
    );
  }
}

/// ISSUED / CANCELLED pill. Public and living beside the dialog because both
/// the list rows and this dialog's header need it — a cancelled invoice must
/// look cancelled everywhere it appears.
class InvoiceStatusPill extends StatelessWidget {
  const InvoiceStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final cancelled = status == invoiceStatusCancelled;
    final fg = cancelled ? AppColors.danger : AppColors.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isEmpty ? invoiceStatusIssued : status,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
