import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/party.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../masters/providers/master_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/invoice_models.dart';
import '../data/invoice_repository.dart';
import '../providers/invoice_providers.dart';
import '../widgets/billable_lr_table.dart';

/// Issue an invoice: pick the customer and a period, tick the delivered LRs to
/// bill, then POST them.
///
/// Everything the customer will read is SNAPSHOTTED by the server at issue
/// time, so every Bill To / Ship To field here is editable even though it is
/// prefilled from the party master — a one-off address correction on this
/// invoice must not require editing (and permanently changing) the master.
///
/// The numbers in the preview are the client's own arithmetic, mirroring
/// `utils/gst.js` and `invoice.service.js`. They are labelled as a preview
/// because the server's figures are the binding ones: it re-reads each LR's
/// freight + margin under a lock, and its seller GSTIN — not the one on screen
/// — decides CGST + SGST vs IGST.
class CreateInvoiceScreen extends ConsumerStatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  ConsumerState<CreateInvoiceScreen> createState() =>
      _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  /// Long enough to swallow a rapid customer-then-range change, short enough
  /// that the table feels immediate.
  static const _queryDebounce = Duration(milliseconds: 250);

  final _billTo = _PartyFields();
  final _shipTo = _PartyFields();
  final _options = _OptionFields();
  final _vendorCode = TextEditingController();

  Party? _customer;
  DateTimeRange? _period;
  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  bool _isTaxInvoice = true;
  bool _shipSameAsBill = true;
  String? _placeOfSupplyCode;
  bool _placeOfSupplyTouched = false;
  bool _optionDefaultsLocked = false;
  bool _submitting = false;
  Timer? _queryTimer;

  /// True between a customer/period change and the debounced provider write, so
  /// the table can show its skeleton instead of the previous query's rows.
  bool _queryPending = false;

  String? _customerError;
  String? _selectionError;
  String? _placeOfSupplyError;
  String? _billGstinError;
  String? _shipGstinError;
  _Notice? _notice;

  @override
  void initState() {
    super.initState();
    // A new invoice always starts blank. billableLrsQueryProvider is app-scoped
    // on purpose (it has to survive the picker dialog), so without this a
    // previous visit's customer would come back beside an empty Bill To block.
    // Deferred out of the build phase — writing a provider from initState
    // throws while the tree is still building.
    Future.microtask(_resetQuery);

    _options.seedDefaults(null);
    // listenManual, not ref.listen: the callback then runs OUTSIDE build, so it
    // may write to the controllers. fireImmediately picks up an already-cached
    // settings row on the first frame instead of leaving the fields blank.
    ref.listenManual<AsyncValue<InvoiceSettings?>>(invoiceSettingsProvider, (
      previous,
      next,
    ) {
      final settings = next.valueOrNull;
      if (settings != null && !_optionDefaultsLocked) {
        _options.seedDefaults(settings);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _queryTimer?.cancel();
    _billTo.dispose();
    _shipTo.dispose();
    _options.dispose();
    _vendorCode.dispose();
    super.dispose();
  }

  void _resetQuery() {
    if (!mounted) return;
    ref.read(billableLrsQueryProvider.notifier).state =
        const BillableLrsQuery();
    ref.read(billableSelectionProvider.notifier).clear();
  }

  /// Pushes the customer + period into the query provider, debounced.
  ///
  /// A stale response cannot overwrite a newer one: `billableLrsProvider` is a
  /// family keyed by the query itself, so each distinct query owns its own
  /// provider and an older one's future is discarded with it when autoDispose
  /// drops it. The query IS the sequence number; the debounce only stops three
  /// requests leaving while the user is still choosing.
  void _scheduleQuery() {
    _queryTimer?.cancel();
    if (!_queryPending) setState(() => _queryPending = true);
    _queryTimer = Timer(_queryDebounce, () {
      if (!mounted) return;
      setState(() => _queryPending = false);
      ref.read(billableLrsQueryProvider.notifier).state = BillableLrsQuery(
        customerId: _customer?.id ?? '',
        from: _period?.start,
        to: _period?.end,
      );
    });
  }

  void _onCustomerChanged(Party? party) {
    setState(() {
      _customer = party;
      _customerError = null;
      if (party != null) _prefillFromParty(party);
    });
    // A different customer is a different invoice: nothing ticked carries over.
    ref.read(billableSelectionProvider.notifier).clear();
    _scheduleQuery();
  }

  /// Seeds the snapshot fields from the master. Called inside setState.
  void _prefillFromParty(Party party) {
    final address = [
      party.address.trim(),
      party.city.trim(),
    ].where((part) => part.isNotEmpty).join(', ');
    final gstin = party.gst.trim().toUpperCase();
    final code = _stateCodeFromGstin(gstin);

    _billTo.name.text = party.name;
    _billTo.address.text = address;
    _billTo.gstin.text = gstin;
    // The party master carries no state column on the client, so the GSTIN —
    // the authoritative source the server itself prefers — names it. Editable
    // either way, and blank rather than guessed when there is no GSTIN.
    _billTo.state.text = code == null ? '' : (_gstStateNames[code] ?? '');
    _billGstinError = null;
    if (!_placeOfSupplyTouched) _placeOfSupplyCode = code;
    // Vendor code is the customer's code FOR US; it is not on the party master,
    // so it stays a per-invoice entry.
    _vendorCode.clear();
  }

  void _onBillGstinChanged(String value) {
    // Re-derive the place of supply from a corrected GSTIN unless the user has
    // chosen one explicitly.
    if (_placeOfSupplyTouched) return;
    final code = _stateCodeFromGstin(value);
    if (code == _placeOfSupplyCode) return;
    setState(() => _placeOfSupplyCode = code);
  }

  void _onShipSameChanged(bool value) {
    setState(() {
      _shipSameAsBill = value;
      _shipGstinError = null;
      if (!value) _shipTo.copyFrom(_billTo);
    });
  }

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _period,
      helpText: 'Bill LRs dated between',
      saveText: 'Apply',
    );
    if (!mounted || picked == null) return;
    // Ticks are kept: `retain` drops only the LRs that left the new range.
    setState(() => _period = picked);
    _scheduleQuery();
  }

  void _clearPeriod() {
    setState(() => _period = null);
    _scheduleQuery();
  }

  @override
  Widget build(BuildContext context) {
    // UI gating only — POST /invoices enforces INVOICE_MANAGE itself.
    if (!ref.watch(canManageInvoicesProvider)) return const _NoAccessView();

    final query = ref.watch(billableLrsQueryProvider);
    final rowsAsync = ref.watch(billableLrsProvider(query));
    final selected = ref.watch(billableSelectionProvider);
    final settingsAsync = ref.watch(invoiceSettingsProvider);

    // Drop ticks for LRs that have left the billable list — a stale id either
    // 404s the create or trips the double-billing guard.
    ref.listen<AsyncValue<List<BillableLr>>>(billableLrsProvider(query), (
      previous,
      next,
    ) {
      final rows = next.valueOrNull;
      if (rows == null) return;
      ref
          .read(billableSelectionProvider.notifier)
          .retain(rows.map((lr) => lr.id));
    });

    final rows = rowsAsync.valueOrNull ?? const <BillableLr>[];
    final picked = rows.where((lr) => selected.contains(lr.id)).toList();
    final previewLines = _previewLines(picked);
    final settings = settingsAsync.valueOrNull;
    final blocker = _settingsNotice(settingsAsync);
    final notice = _notice;
    final mobile = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'New Invoice',
            subtitle: 'Bill a customer for delivered LRs',
            actions: [
              AppButton(
                label: 'Cancel',
                kind: BtnKind.ghost,
                small: true,
                onPressed: _submitting ? null : () => context.go('/invoices'),
              ),
              AppButton(
                label: 'Issue invoice',
                icon: Icons.receipt_long_rounded,
                small: true,
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(mobile ? 14 : 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (blocker != null) _NoticeBanner(notice: blocker),
                      if (notice != null)
                        _NoticeBanner(
                          notice: notice,
                          onDismiss: () => setState(() => _notice = null),
                        ),
                      _CustomerCard(
                        // Consignor parties, NOT customer-tagged ones. The
                        // server selects billable LRs with consignor_id =
                        // customer_id (invoice.service.js billableLrs), so a
                        // party tagged is_customer but not is_consignor can
                        // never match an LR and the picker would just return an
                        // empty list every time.
                        customers: ref.watch(consignorPartiesProvider),
                        selected: _customer,
                        onChanged: _onCustomerChanged,
                        period: _period,
                        onPickPeriod: _pickPeriod,
                        onClearPeriod: _clearPeriod,
                        errorText: _customerError,
                      ),
                      const SizedBox(height: 16),
                      BillableLrTable(
                        rows: rowsAsync,
                        selected: selected,
                        hasCustomer: query.hasCustomer || _customer != null,
                        pending: _queryPending,
                        selectionError: _selectionError,
                        onToggle: (id) => ref
                            .read(billableSelectionProvider.notifier)
                            .toggle(id),
                        onSelectAll: (ids) => ref
                            .read(billableSelectionProvider.notifier)
                            .selectAll(ids),
                        onClearSelection: () => ref
                            .read(billableSelectionProvider.notifier)
                            .clear(),
                        onRetry: () =>
                            ref.invalidate(billableLrsProvider(query)),
                      ),
                      const SizedBox(height: 16),
                      _BillingCard(
                        billTo: _billTo,
                        shipTo: _shipTo,
                        vendorCode: _vendorCode,
                        shipSameAsBill: _shipSameAsBill,
                        onShipSameChanged: _onShipSameChanged,
                        billGstinError: _billGstinError,
                        shipGstinError: _shipGstinError,
                        onBillGstinChanged: _onBillGstinChanged,
                      ),
                      const SizedBox(height: 16),
                      _OptionsCard(
                        options: _options,
                        isTaxInvoice: _isTaxInvoice,
                        onTaxInvoiceChanged: (value) => setState(() {
                          _isTaxInvoice = value;
                          _placeOfSupplyError = null;
                        }),
                        invoiceDate: _invoiceDate,
                        onInvoiceDateChanged: (value) =>
                            setState(() => _invoiceDate = value),
                        dueDate: _dueDate,
                        onDueDateChanged: (value) =>
                            setState(() => _dueDate = value),
                        placeOfSupplyCode: _placeOfSupplyCode,
                        placeOfSupplyError: _placeOfSupplyError,
                        onPlaceOfSupplyChanged: (code) => setState(() {
                          _placeOfSupplyCode = code;
                          _placeOfSupplyTouched = true;
                          _placeOfSupplyError = null;
                        }),
                        onEdited: () =>
                            setState(() => _optionDefaultsLocked = true),
                      ),
                      const SizedBox(height: 16),
                      _PreviewCard(
                        lines: previewLines,
                        tax: _previewTax(
                          lines: previewLines,
                          settings: settings,
                          isTaxInvoice: _isTaxInvoice,
                          placeOfSupplyCode: _placeOfSupplyCode,
                        ),
                        title: _options.lineTitle.text.trim(),
                        hsnSac: _options.hsnSac.text.trim(),
                        placeOfSupply: _placeOfSupplyCode == null
                            ? ''
                            : (_gstStateNames[_placeOfSupplyCode] ?? ''),
                      ),
                      const SizedBox(height: 20),
                      AppButton(
                        label: 'Issue invoice',
                        icon: Icons.receipt_long_rounded,
                        expanded: true,
                        loading: _submitting,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one blocking condition the operator must be told about before they
  /// fill anything in: the server refuses to issue without a letterhead row.
  _Notice? _settingsNotice(AsyncValue<InvoiceSettings?> async) {
    return switch (async) {
      AsyncData(:final value) when value == null => const _Notice(
        kind: _NoticeKind.warning,
        title: 'Invoice settings are not configured',
        message:
            'No invoice can be issued until an admin fills in the letterhead, '
            'bank details and seller GSTIN under Admin › Invoice Settings.',
      ),
      AsyncData(:final value) when value?.hasSellerGstin == false =>
        const _Notice(
          kind: _NoticeKind.warning,
          title: 'Seller GSTIN is missing',
          message:
              "Invoice settings carry no seller GSTIN, so the seller's state "
              'cannot be determined and a tax invoice cannot be issued. An '
              'admin can add it under Admin › Invoice Settings.',
        ),
      AsyncError(:final error) => _Notice(
        kind: _NoticeKind.warning,
        title: 'Could not load invoice settings',
        message: friendlyErrorMessage(error),
      ),
      _ => null,
    };
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final query = ref.read(billableLrsQueryProvider);
    final rows =
        ref.read(billableLrsProvider(query)).valueOrNull ??
        const <BillableLr>[];
    final selected = ref.read(billableSelectionProvider);
    final lrIds = rows
        .where((lr) => selected.contains(lr.id))
        .map((lr) => lr.id)
        .toList();
    final settings = ref.read(invoiceSettingsProvider);
    final customer = _customer;

    if (!_validate(customer: customer, lrIds: lrIds, settings: settings)) {
      return;
    }
    // Unreachable — _validate already flags a null customer. Kept so the null
    // check promotes `customer` for the rest of the method.
    if (customer == null) return;

    setState(() {
      _submitting = true;
      _notice = null;
    });

    try {
      final invoice = await ref
          .read(invoiceRepositoryProvider)
          .create(_payload(customer: customer, lrIds: lrIds));
      if (!mounted) return;
      ref.read(billableSelectionProvider.notifier).clear();
      ref.invalidate(invoiceListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice ${invoice.number} issued')),
      );
      if (!context.mounted) return;
      // Plain /invoices. The list is invalidated above and orders newest first,
      // so the invoice just issued is the top row. No ?open= parameter: nothing
      // reads one, and a query string promising an auto-open that never happens
      // is worse than not promising it.
      context.go('/invoices');
      return;
    } on AlreadyInvoicedException catch (e) {
      if (!mounted) return;
      _handleClash(e, rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = _failureNotice(e));
    } finally {
      // The success path has navigated away by now, so this only runs while the
      // screen is still alive.
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _validate({
    required Party? customer,
    required List<String> lrIds,
    required AsyncValue<InvoiceSettings?> settings,
  }) {
    final billGstin = _billTo.gstin.text.trim().toUpperCase();
    final shipGstin = _shipTo.gstin.text.trim().toUpperCase();
    final needsPlaceOfSupply = _isTaxInvoice && _placeOfSupplyCode == null;

    setState(() {
      _customerError = customer == null ? 'Pick the customer to bill.' : null;
      _selectionError = lrIds.isEmpty
          ? 'Tick at least one LR to invoice.'
          : null;
      _placeOfSupplyError = needsPlaceOfSupply
          ? 'Pick the place of supply — it decides CGST + SGST vs IGST.'
          : null;
      _billGstinError = billGstin.isNotEmpty && !_isValidGstin(billGstin)
          ? 'Not a valid 15-character GSTIN.'
          : null;
      _shipGstinError =
          !_shipSameAsBill && shipGstin.isNotEmpty && !_isValidGstin(shipGstin)
          ? 'Not a valid 15-character GSTIN.'
          : null;
    });

    // Only a SETTLED "there is no settings row" blocks the issue here. While
    // the row is still loading (or its fetch failed) the server stays the
    // authority: it answers NO_SETTINGS, which _failureNotice renders with the
    // same words. Blocking on a merely-unresolved provider would refuse a
    // perfectly valid invoice.
    final configured = switch (settings) {
      AsyncData(:final value) => value != null,
      _ => true,
    };
    if (!configured) {
      setState(
        () => _notice = const _Notice(
          kind: _NoticeKind.error,
          title: 'Invoice settings are not configured',
          message:
              'The server will not issue an invoice without a letterhead. Ask '
              'an admin to complete Admin › Invoice Settings first.',
        ),
      );
      return false;
    }

    return _customerError == null &&
        _selectionError == null &&
        _placeOfSupplyError == null &&
        _billGstinError == null &&
        _shipGstinError == null;
  }

  Map<String, dynamic> _payload({
    required Party customer,
    required List<String> lrIds,
  }) {
    String? text(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    String? upper(TextEditingController controller) =>
        text(controller)?.toUpperCase();

    final dueDate = _dueDate;
    final posCode = _placeOfSupplyCode;
    final posName = posCode == null ? null : _gstStateNames[posCode];

    return <String, dynamic>{
      'customer_id': customer.id,
      'lr_ids': lrIds,
      'invoice_date': invoiceDateOnly(_invoiceDate),
      // Omitted rather than null: the server then applies the customer master's
      // payment terms, which the client cannot see.
      if (dueDate != null) 'due_date': invoiceDateOnly(dueDate),
      'is_tax_invoice': _isTaxInvoice,
      if (posCode != null && posName != null) ...{
        'place_of_supply': posName,
        'place_of_supply_code': posCode,
      },
      if (text(_billTo.name) != null) 'bill_to_name': text(_billTo.name),
      if (text(_billTo.address) != null)
        'bill_to_address': text(_billTo.address),
      if (upper(_billTo.gstin) != null) 'bill_to_gstin': upper(_billTo.gstin),
      if (text(_billTo.state) != null) 'bill_to_state': text(_billTo.state),
      // Ship To is omitted entirely when it mirrors Bill To — the server copies
      // it across, so sending it would only duplicate the snapshot.
      if (!_shipSameAsBill) ...{
        if (text(_shipTo.name) != null) 'ship_to_name': text(_shipTo.name),
        if (text(_shipTo.address) != null)
          'ship_to_address': text(_shipTo.address),
        if (upper(_shipTo.gstin) != null) 'ship_to_gstin': upper(_shipTo.gstin),
        if (text(_shipTo.state) != null) 'ship_to_state': text(_shipTo.state),
      },
      if (text(_vendorCode) != null) 'vendor_code': text(_vendorCode),
      if (text(_options.referenceNo) != null)
        'reference_no': text(_options.referenceNo),
      if (text(_options.otherReference) != null)
        'other_reference': text(_options.otherReference),
      if (text(_options.notes) != null) 'notes': text(_options.notes),
      if (text(_options.hsnSac) != null) 'hsn_sac': text(_options.hsnSac),
      if (text(_options.serviceMode) != null)
        'service_mode': text(_options.serviceMode),
      if (text(_options.lineTitle) != null)
        'line_title': text(_options.lineTitle),
    };
  }

  /// Someone else billed one of these LRs first. Name them, untick exactly
  /// those rows, refresh the billable list — and touch nothing else the user
  /// has typed: losing a half-filled invoice to a race is the worst outcome
  /// this screen has.
  void _handleClash(AlreadyInvoicedException e, List<BillableLr> rows) {
    final clashed = e.lrNumbers.toSet();
    final selection = ref.read(billableSelectionProvider.notifier);
    for (final lr in rows) {
      if (clashed.contains(lr.number) && selection.isSelected(lr.id)) {
        selection.toggle(lr.id);
      }
    }
    ref.invalidate(billableLrsProvider(ref.read(billableLrsQueryProvider)));
    setState(
      () => _notice = _Notice(
        kind: _NoticeKind.error,
        title: 'Some LRs were billed by someone else',
        // The server's sentence already names them and says what to do.
        message: e.message,
      ),
    );
  }

  _Notice _failureNotice(Object error) {
    final api = asApiException(error);
    if (api != null && api.code == 'NO_SETTINGS') {
      return const _Notice(
        kind: _NoticeKind.error,
        title: 'Invoice settings are not configured',
        message:
            'The server will not issue an invoice without a letterhead. Ask an '
            'admin to complete Admin › Invoice Settings, then try again.',
      );
    }
    return _Notice(
      kind: _NoticeKind.error,
      title: 'The invoice was not issued',
      message: friendlyErrorMessage(error),
    );
  }
}

// ---- Field bundles ---------------------------------------------------------

/// The four snapshot fields of a Bill To / Ship To block, bundled so the screen
/// disposes them in one place and passes them as one argument.
class _PartyFields {
  final name = TextEditingController();
  final address = TextEditingController();
  final gstin = TextEditingController();
  final state = TextEditingController();

  void copyFrom(_PartyFields other) {
    name.text = other.name.text;
    address.text = other.address.text;
    gstin.text = other.gstin.text;
    state.text = other.state.text;
  }

  void dispose() {
    name.dispose();
    address.dispose();
    gstin.dispose();
    state.dispose();
  }
}

/// Defaults that mirror `invoice.service.js` when INVOICE_SETTINGS carries
/// none, so the fields are never blank while the settings row loads.
const _fallbackHsnSac = '996511';
const _fallbackServiceMode = 'Express';
const _fallbackLineTitle = 'Freight Charge-';

class _OptionFields {
  final hsnSac = TextEditingController();
  final serviceMode = TextEditingController();
  final lineTitle = TextEditingController();
  final referenceNo = TextEditingController();
  final otherReference = TextEditingController();
  final notes = TextEditingController();

  void seedDefaults(InvoiceSettings? settings) {
    hsnSac.text = _orElse(settings?.defaultHsnSac, _fallbackHsnSac);
    serviceMode.text = _orElse(
      settings?.defaultServiceMode,
      _fallbackServiceMode,
    );
    lineTitle.text = _orElse(settings?.defaultLineTitle, _fallbackLineTitle);
  }

  static String _orElse(String? value, String fallback) =>
      (value == null || value.isEmpty) ? fallback : value;

  void dispose() {
    hsnSac.dispose();
    serviceMode.dispose();
    lineTitle.dispose();
    referenceNo.dispose();
    otherReference.dispose();
    notes.dispose();
  }
}

// ---- Cards -----------------------------------------------------------------

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customers,
    required this.selected,
    required this.onChanged,
    required this.period,
    required this.onPickPeriod,
    required this.onClearPeriod,
    required this.errorText,
  });

  final List<Party> customers;
  final Party? selected;
  final ValueChanged<Party?> onChanged;
  final DateTimeRange? period;
  final VoidCallback onPickPeriod;
  final VoidCallback onClearPeriod;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.business_outlined,
            title: 'Customer & period',
          ),
          _FieldGrid(
            children: [
              LabeledField(
                label: 'Customer',
                required: true,
                errorText: errorText,
                child: SearchableField<Party>(
                  value: selected,
                  options: customers,
                  labelOf: (p) => p.name,
                  subtitleOf: (p) => p.gst.isNotEmpty ? 'GST ${p.gst}' : p.city,
                  hintText: 'Select customer',
                  dialogTitle: 'Select Customer',
                  onChanged: onChanged,
                ),
              ),
              LabeledField(
                label: 'LR period (optional)',
                child: _RangeField(
                  value: period,
                  onTap: onPickPeriod,
                  onClear: onClearPeriod,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillingCard extends StatelessWidget {
  const _BillingCard({
    required this.billTo,
    required this.shipTo,
    required this.vendorCode,
    required this.shipSameAsBill,
    required this.onShipSameChanged,
    required this.billGstinError,
    required this.shipGstinError,
    required this.onBillGstinChanged,
  });

  final _PartyFields billTo;
  final _PartyFields shipTo;
  final TextEditingController vendorCode;
  final bool shipSameAsBill;
  final ValueChanged<bool> onShipSameChanged;
  final String? billGstinError;
  final String? shipGstinError;
  final ValueChanged<String> onBillGstinChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.assignment_ind_outlined,
            title: 'Bill To / Ship To',
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Prefilled from the customer master and printed exactly as typed '
              '— the invoice stores its own copy, so correcting an address '
              'here changes this document only.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
          ),
          _PartyBlock(
            title: 'Bill To',
            fields: billTo,
            gstinError: billGstinError,
            onGstinChanged: onBillGstinChanged,
          ),
          const SizedBox(height: 14),
          _FieldGrid(
            children: [
              LabeledField(
                label: 'Vendor code',
                child: TextField(
                  controller: vendorCode,
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  decoration: const InputDecoration(
                    hintText: "The customer's code for us",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _CheckRow(
            label: 'Ship To is the same as Bill To',
            value: shipSameAsBill,
            onChanged: onShipSameChanged,
          ),
          if (!shipSameAsBill) ...[
            const SizedBox(height: 10),
            _PartyBlock(
              title: 'Ship To',
              fields: shipTo,
              gstinError: shipGstinError,
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
    required this.fields,
    required this.gstinError,
    this.onGstinChanged,
  });

  final String title;
  final _PartyFields fields;
  final String? gstinError;
  final ValueChanged<String>? onGstinChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.plum,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _FieldGrid(
          children: [
            LabeledField(
              label: 'Name',
              child: TextField(
                controller: fields.name,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                decoration: const InputDecoration(hintText: 'Party name'),
              ),
            ),
            LabeledField(
              label: 'GSTIN',
              errorText: gstinError,
              child: TextField(
                controller: fields.gstin,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [LengthLimitingTextInputFormatter(15)],
                decoration: const InputDecoration(hintText: '27AAAAA0000A1Z5'),
                onChanged: onGstinChanged,
              ),
            ),
            LabeledField(
              label: 'State',
              child: TextField(
                controller: fields.state,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                decoration: const InputDecoration(hintText: 'Maharashtra'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Address',
          child: TextField(
            controller: fields.address,
            minLines: 2,
            maxLines: 4,
            inputFormatters: [LengthLimitingTextInputFormatter(2000)],
            decoration: const InputDecoration(
              hintText: 'Address printed on the invoice',
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({
    required this.options,
    required this.isTaxInvoice,
    required this.onTaxInvoiceChanged,
    required this.invoiceDate,
    required this.onInvoiceDateChanged,
    required this.dueDate,
    required this.onDueDateChanged,
    required this.placeOfSupplyCode,
    required this.placeOfSupplyError,
    required this.onPlaceOfSupplyChanged,
    required this.onEdited,
  });

  final _OptionFields options;
  final bool isTaxInvoice;
  final ValueChanged<bool> onTaxInvoiceChanged;
  final DateTime invoiceDate;
  final ValueChanged<DateTime> onInvoiceDateChanged;
  final DateTime? dueDate;
  final ValueChanged<DateTime?> onDueDateChanged;
  final String? placeOfSupplyCode;
  final String? placeOfSupplyError;
  final ValueChanged<String?> onPlaceOfSupplyChanged;
  final VoidCallback onEdited;

  @override
  Widget build(BuildContext context) {
    final states = _gstStateNames.entries.toList();
    final selectedState = states
        .where((entry) => entry.key == placeOfSupplyCode)
        .firstOrNull;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.tune_rounded,
            title: 'Invoice options',
          ),
          _TaxChoice(value: isTaxInvoice, onChanged: onTaxInvoiceChanged),
          const SizedBox(height: 16),
          _FieldGrid(
            children: [
              LabeledField(
                label: 'Invoice date',
                required: true,
                child: _DateField(
                  value: invoiceDate,
                  onChanged: (value) {
                    if (value != null) onInvoiceDateChanged(value);
                  },
                ),
              ),
              LabeledField(
                label: 'Due date',
                child: _DateField(
                  value: dueDate,
                  clearable: true,
                  hint: "Customer's payment terms",
                  onChanged: onDueDateChanged,
                ),
              ),
              LabeledField(
                label: 'Place of supply',
                required: isTaxInvoice,
                errorText: placeOfSupplyError,
                child: SearchableField<MapEntry<String, String>>(
                  value: selectedState,
                  options: states,
                  clearable: true,
                  labelOf: (entry) => entry.value,
                  subtitleOf: (entry) => 'State code ${entry.key}',
                  hintText: 'Select state',
                  dialogTitle: 'Place of supply',
                  onChanged: (entry) => onPlaceOfSupplyChanged(entry?.key),
                ),
              ),
              LabeledField(
                label: 'HSN / SAC',
                child: TextField(
                  controller: options.hsnSac,
                  inputFormatters: [LengthLimitingTextInputFormatter(16)],
                  decoration: const InputDecoration(hintText: _fallbackHsnSac),
                  onChanged: (_) => onEdited(),
                ),
              ),
              LabeledField(
                label: 'Service mode',
                child: TextField(
                  controller: options.serviceMode,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  decoration: const InputDecoration(
                    hintText: _fallbackServiceMode,
                  ),
                  onChanged: (_) => onEdited(),
                ),
              ),
              LabeledField(
                label: 'Line title',
                child: TextField(
                  controller: options.lineTitle,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  decoration: const InputDecoration(
                    hintText: _fallbackLineTitle,
                  ),
                  onChanged: (_) => onEdited(),
                ),
              ),
              LabeledField(
                label: 'Reference no',
                child: TextField(
                  controller: options.referenceNo,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  decoration: const InputDecoration(
                    hintText: 'PO / contract number',
                  ),
                ),
              ),
              LabeledField(
                label: 'Other reference',
                child: TextField(
                  controller: options.otherReference,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  decoration: const InputDecoration(hintText: 'Optional'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Notes',
            child: TextField(
              controller: options.notes,
              minLines: 2,
              maxLines: 4,
              inputFormatters: [LengthLimitingTextInputFormatter(2000)],
              decoration: const InputDecoration(
                hintText: 'Printed under the items table',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live preview of the document that will be issued: the selected LRs
/// grouped into printed lines, then the totals.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.lines,
    required this.tax,
    required this.title,
    required this.hsnSac,
    required this.placeOfSupply,
  });

  final List<_PreviewLine> lines;
  final _TaxPreview tax;
  final String title;
  final String hsnSac;
  final String placeOfSupply;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.description_outlined,
            title: 'Invoice preview',
          ),
          const _PreviewDisclaimer(),
          const SizedBox(height: 12),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Tick the LRs above to see the lines that will be printed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.slate),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                return Column(
                  children: [
                    for (final line in lines)
                      _PreviewRow(
                        line: line,
                        title: title.isEmpty ? _fallbackLineTitle : title,
                        hsnSac: hsnSac,
                        wide: wide,
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 14),
          _TotalRow(label: 'Sub Total', value: inrPaise(tax.subTotal)),
          for (final head in tax.heads)
            _TotalRow(label: head.label, value: inrPaise(head.amount)),
          if (tax.unresolved)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Pick the place of supply to preview the GST split.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warn,
                ),
              ),
            ),
          const Divider(height: 18, color: AppColors.line),
          // With the split unresolved, tax.total is still the PRE-TAX subtotal.
          // Printing that as an emphasised "Total" on a document flagged as a
          // tax invoice understates it by the whole GST, so show nothing rather
          // than a confidently wrong figure.
          _TotalRow(
            label: 'Total',
            value: tax.unresolved ? '—' : inrPaise(tax.total),
            emphasis: true,
          ),
          if (placeOfSupply.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Place of supply: $placeOfSupply',
                style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewDisclaimer extends StatelessWidget {
  const _PreviewDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.warn,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Preview only. The server computes the binding figures when the '
              'invoice is issued — it re-reads each LR and applies the seller '
              'GSTIN held in Invoice Settings.',
              style: TextStyle(fontSize: 11.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.line,
    required this.title,
    required this.hsnSac,
    required this.wide,
  });

  final _PreviewLine line;
  final String title;
  final String hsnSac;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    );
    const metaStyle = TextStyle(fontSize: 11.5, color: AppColors.slate);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: labelStyle),
                const SizedBox(height: 2),
                Text(
                  wide
                      ? '${line.qty} LR${line.qty == 1 ? '' : 's'}'
                      : '${line.qty} × ${inrPaise(line.rate)}'
                            '${hsnSac.isEmpty ? '' : ' · HSN $hsnSac'}',
                  style: metaStyle,
                ),
              ],
            ),
          ),
          if (wide) ...[
            SizedBox(
              width: 90,
              child: Text(
                hsnSac.isEmpty ? '—' : hsnSac,
                style: metaStyle,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '${line.qty}',
                style: labelStyle,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                inrPaise(line.rate),
                style: labelStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
          SizedBox(
            width: wide ? 120 : 100,
            child: Text(
              inrPaise(line.amount),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: emphasis ? 14 : 12.5,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                color: emphasis ? AppColors.ink : AppColors.slate,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasis ? 16 : 13,
              fontWeight: FontWeight.w800,
              color: emphasis ? AppColors.plum : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Small shared pieces ---------------------------------------------------

/// Responsive form grid: three columns wide, two on a tablet, one on a phone.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : (constraints.maxWidth >= 560 ? 2 : 1);
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.onChanged,
    this.hint = 'Pick a date',
    this.clearable = false,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String hint;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final current = value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: current ?? now,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 2, 12, 31),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        isEmpty: current == null,
        decoration: InputDecoration(
          suffixIcon: clearable && current != null
              ? IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.slate,
                  onPressed: () => onChanged(null),
                )
              : const Icon(
                  Icons.event_outlined,
                  color: AppColors.slate,
                  size: 20,
                ),
        ),
        child: Text(
          current == null ? hint : formatDate(current),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: current == null ? AppColors.slate : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final DateTimeRange? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final range = value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: range == null,
        decoration: InputDecoration(
          suffixIcon: range == null
              ? const Icon(
                  Icons.date_range_outlined,
                  color: AppColors.slate,
                  size: 20,
                )
              : IconButton(
                  tooltip: 'Clear period',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.slate,
                  onPressed: onClear,
                ),
        ),
        child: Text(
          range == null
              ? 'All unbilled LRs'
              : '${formatDate(range.start)} – ${formatDate(range.end)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: range == null ? AppColors.slate : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Tax invoice vs plain invoice, as one visible two-way choice rather than a
/// checkbox — it changes what the customer can claim, so it must not be a
/// setting someone can miss.
class _TaxChoice extends StatelessWidget {
  const _TaxChoice({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ChoicePill(
          label: 'Tax invoice (with GST)',
          icon: Icons.verified_outlined,
          selected: value,
          onTap: () => onChanged(true),
        ),
        _ChoicePill(
          label: 'Invoice (no GST)',
          icon: Icons.receipt_outlined,
          selected: !value,
          onTap: () => onChanged(false),
        ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.plum.withValues(alpha: 0.1)
                  : AppColors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.plum : AppColors.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.plum : AppColors.slate,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.plum : AppColors.slate,
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

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: AppColors.plum,
              onChanged: (next) => onChanged(next ?? false),
            ),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NoticeKind { warning, error }

class _Notice {
  const _Notice({
    required this.kind,
    required this.title,
    required this.message,
  });

  final _NoticeKind kind;
  final String title;
  final String message;
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice, this.onDismiss});

  final _Notice notice;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = notice.kind == _NoticeKind.error
        ? AppColors.danger
        : AppColors.warn;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.kind == _NoticeKind.error
                ? Icons.error_outline_rounded
                : Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notice.message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.slate,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

class _NoAccessView extends StatelessWidget {
  const _NoAccessView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'New Invoice',
            subtitle: 'Bill a customer for delivered LRs',
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.plum.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.plum,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'You cannot issue invoices',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Issuing an invoice needs the Invoice Manage permission. '
                      'Ask an admin if you should have it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Back to invoices',
                      kind: BtnKind.ghost,
                      small: true,
                      onPressed: () => context.go('/invoices'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Preview arithmetic ----------------------------------------------------
//
// A deliberate mirror of invoice.service.js (groupLrsIntoLines) and gst.js
// (computeTax). It exists so the operator can see what they are about to issue;
// the server recomputes all of it from the LRs under a lock, and its answer is
// the one that is stored and printed.

/// Standard GST on goods transport under forward charge (HSN 996511) — the
/// server's DEFAULT_GST_RATE, used only when settings carry no rate.
const double _defaultGstRate = 18;

double _round2(double value) => (value * 100).roundToDouble() / 100;

class _PreviewLine {
  const _PreviewLine({
    required this.rate,
    required this.qty,
    required this.amount,
  });

  final double rate;
  final int qty;
  final double amount;
}

/// One line per DISTINCT billed amount, qty = how many LRs share it, highest
/// rate first. Rates are distinct by construction, so the server's date
/// tie-break can never apply here.
List<_PreviewLine> _previewLines(Iterable<BillableLr> lrs) {
  final groups = <String, List<BillableLr>>{};
  for (final lr in lrs) {
    // An LR whose amount the server withheld cannot be priced here at all.
    // Grouping it under 0 would invent a ₹0 line and understate the invoice, so
    // it is left out of the preview entirely — the server still prices it on
    // issue, and the table shows a "amounts hidden" caveat beside the selection.
    final amount = lr.billedAmount;
    if (amount == null) continue;
    // Keyed on the fixed-point string, exactly as the server does, so 5000 and
    // 5000.004 cannot collapse into one line.
    final key = _round2(amount).toStringAsFixed(2);
    groups.putIfAbsent(key, () => <BillableLr>[]).add(lr);
  }
  final lines = [
    for (final group in groups.values)
      _PreviewLine(
        rate: _round2(group.first.billedAmount ?? 0),
        qty: group.length,
        amount: _round2(_round2(group.first.billedAmount ?? 0) * group.length),
      ),
  ]..sort((a, b) => b.rate.compareTo(a.rate));
  return lines;
}

class _TaxHead {
  const _TaxHead({required this.label, required this.amount});

  final String label;
  final double amount;
}

class _TaxPreview {
  const _TaxPreview({
    required this.subTotal,
    required this.heads,
    required this.total,
    required this.unresolved,
  });

  final double subTotal;
  final List<_TaxHead> heads;
  final double total;

  /// True when this is a tax invoice but the seller or buyer state code is not
  /// known yet, so no split can be shown. The server refuses to issue in that
  /// state (INVALID_STATE) rather than guessing, and so does this screen.
  final bool unresolved;
}

/// The split the invoice will most likely carry.
///
/// Same rules as `gst.js`: the seller's state comes from the GSTIN in invoice
/// settings, the buyer's from the chosen place of supply; equal codes mean
/// CGST + SGST at half the rate each, different codes mean IGST at the full
/// rate. Each intra head is its OWN rate applied to the taxable value — never
/// half of a pre-rounded total, which lands the two heads a paisa apart.
_TaxPreview _previewTax({
  required List<_PreviewLine> lines,
  required InvoiceSettings? settings,
  required bool isTaxInvoice,
  required String? placeOfSupplyCode,
}) {
  final subTotal = _round2(
    lines.fold<double>(0, (sum, line) => sum + line.amount),
  );

  if (!isTaxInvoice) {
    return _TaxPreview(
      subTotal: subTotal,
      heads: const [],
      total: subTotal,
      unresolved: false,
    );
  }

  final sellerCode = _stateCodeFromGstin(settings?.effectiveSellerGstin);
  if (sellerCode == null || placeOfSupplyCode == null) {
    return _TaxPreview(
      subTotal: subTotal,
      heads: const [],
      total: subTotal,
      unresolved: true,
    );
  }

  final rate = settings?.gstRate ?? _defaultGstRate;
  if (sellerCode == placeOfSupplyCode) {
    final halfRate = _round2(rate / 2);
    final head = _round2(subTotal * halfRate / 100);
    return _TaxPreview(
      subTotal: subTotal,
      heads: [
        _TaxHead(label: 'CGST ${pctText(halfRate)}%', amount: head),
        _TaxHead(label: 'SGST ${pctText(halfRate)}%', amount: head),
      ],
      total: _round2(subTotal + head + head),
      unresolved: false,
    );
  }

  final igst = _round2(subTotal * rate / 100);
  return _TaxPreview(
    subTotal: subTotal,
    heads: [_TaxHead(label: 'IGST ${pctText(rate)}%', amount: igst)],
    total: _round2(subTotal + igst),
    unresolved: false,
  );
}

// ---- GST state codes -------------------------------------------------------

/// 15 chars: 2 state digits + 10 PAN chars + entity code + a slot + checksum.
/// The same expression `utils/gst.js` validates with, so a GSTIN this screen
/// accepts is one the server's Joi schema accepts too.
final _gstinPattern = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]{3}$');

bool _isValidGstin(String value) =>
    _gstinPattern.hasMatch(value.trim().toUpperCase());

/// The buyer's state code, read from the only authoritative source there is.
/// Null when the GSTIN is malformed or its prefix is not a real state code.
String? _stateCodeFromGstin(String? gstin) {
  final value = (gstin ?? '').trim().toUpperCase();
  if (!_gstinPattern.hasMatch(value)) return null;
  final code = value.substring(0, 2);
  return _gstStateNames.containsKey(code) ? code : null;
}

/// Official GST state codes, mirroring STATE_CODES in `utils/gst.js` — this is
/// the exact set the server's `normalizeStateCode` accepts, so a code picked
/// here can never be rejected as unknown. 25 and 28 are superseded but kept:
/// GSTINs issued before the 2020 UT merger and the 2014 Andhra bifurcation are
/// still on live customer masters.
const Map<String, String> _gstStateNames = {
  '01': 'Jammu and Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '25': 'Daman and Diu',
  '26': 'Dadra and Nagar Haveli and Daman and Diu',
  '27': 'Maharashtra',
  '28': 'Andhra Pradesh (Before Division)',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman and Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
  '97': 'Other Territory',
  '99': 'Centre Jurisdiction',
};
