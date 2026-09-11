import '../../../core/utils/formatters.dart';
import '../../../core/utils/json_parse.dart';

// Sales invoices — the client-side mirror of lr_management's invoice tables.
//
// Everything a printed invoice shows is SNAPSHOTTED on the server when the
// invoice is issued (party address, LR number/date/vehicle/mode, and the GST
// rates themselves), because an invoice is a legal document that a later edit
// to a master must never rewrite. These models therefore only ever READ what
// the server stored — no amount, tax or total is recomputed here.
//
// Money columns are Postgres NUMERIC and arrive as STRINGS, so every one of
// them goes through asDouble/asDoubleOrNull. Dates on the wire are YYYY-MM-DD.

/// `YYYY-MM-DD` — the wire format every invoice date field uses, both in query
/// strings and in the create payload. Built from LOCAL components, so a picked
/// date can never shift onto the previous calendar day.
String invoiceDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _str(dynamic v) => v == null ? '' : v.toString();

DateTime? _dateOrNull(dynamic v) => DateTime.tryParse(_str(v));

List<Map<String, dynamic>> _maps(dynamic v) => ((v as List?) ?? const [])
    .whereType<Map>()
    .map((e) => e.cast<String, dynamic>())
    .toList();

List<String> _strings(dynamic v) =>
    ((v as List?) ?? const []).map(_str).toList();

/// Invoice status, as stored in `invoices.status`.
const String invoiceStatusIssued = 'ISSUED';
const String invoiceStatusCancelled = 'CANCELLED';

/// Tax mode, as stored in `invoices.tax_mode`. INTRA = CGST + SGST (buyer in
/// the seller's state), INTER = IGST, NONE = the untaxed layout.
const String invoiceTaxModeIntra = 'INTRA';
const String invoiceTaxModeInter = 'INTER';
const String invoiceTaxModeNone = 'NONE';

/// One row of `GET /invoices/billable-lrs` — a DELIVERED LR for this customer
/// that carries no bill number and sits on no live invoice. The server has
/// already excluded everything else, so the create screen never re-filters.
class BillableLr {
  final String id;
  final String number;

  /// The LR date. Non-null on the server (`lrs.lr_date`); an unparsable value
  /// falls back to now — the same tolerance `LorryReceipt` applies — so one bad
  /// row cannot fail the whole list.
  final DateTime lrDate;
  final String vehicleNo;

  /// Service mode — 'Express' when the LR carries express charges, else ''.
  final String mode;
  final String fromCity;
  final String toCity;
  final String customerName;

  /// Always 'DELIVERED' today; kept because the server sends it.
  final String statusCode;

  /// freight + vistar_margin — the same figure the MIS sheet calls "Vistar
  /// Billing Amount". Never re-derived on the client.
  ///
  /// NULL when the server withheld it: billableLrs releases this figure only to
  /// a holder of all three rate permissions, because any two of billing amount,
  /// freight and margin give the third. Nullable rather than 0 on purpose — a
  /// zero would render as a real ₹0.00 and price the invoice at nothing.
  final double? billedAmount;

  const BillableLr({
    required this.id,
    required this.number,
    required this.lrDate,
    this.vehicleNo = '',
    this.mode = '',
    this.fromCity = '',
    this.toCity = '',
    this.customerName = '',
    this.statusCode = '',
    this.billedAmount,
  });

  /// False when the server withheld the amount for this caller.
  bool get hasAmount => billedAmount != null;

  String get route =>
      fromCity.isEmpty && toCity.isEmpty ? '' : '$fromCity → $toCity';

  factory BillableLr.fromJson(Map<String, dynamic> json) => BillableLr(
    id: _str(json['id']),
    number: _str(json['number']),
    lrDate: _dateOrNull(json['lr_date']) ?? DateTime.now(),
    vehicleNo: _str(json['vehicle_no']),
    mode: _str(json['mode']),
    fromCity: _str(json['from_city']),
    toCity: _str(json['to_city']),
    customerName: _str(json['customer_name']),
    statusCode: _str(json['status_code']),
    billedAmount: asDoubleOrNull(json['billed_amount']),
  );
}

/// One LR printed under an invoice line — a snapshot taken at issue time, not
/// a live view of the LR.
class InvoiceLineLr {
  final String lrId;
  final String lrNumber;
  final DateTime? lrDate;
  final String vehicleNo;
  final String mode;
  final double amount;

  const InvoiceLineLr({
    required this.lrId,
    this.lrNumber = '',
    this.lrDate,
    this.vehicleNo = '',
    this.mode = '',
    this.amount = 0,
  });

  /// "MH20EG8749 || LR/SBN/26-27/00847 || 01 Aug 2026 || Express" — the order
  /// the PDF prints, with empty parts dropped.
  String get description {
    final date = lrDate;
    return [
      vehicleNo,
      lrNumber,
      if (date != null) formatDate(date),
      mode,
    ].where((part) => part.isNotEmpty).join(' || ');
  }

  factory InvoiceLineLr.fromJson(Map<String, dynamic> json) => InvoiceLineLr(
    lrId: _str(json['lr_id']),
    lrNumber: _str(json['lr_number']),
    lrDate: _dateOrNull(json['lr_date']),
    vehicleNo: _str(json['vehicle_no']),
    mode: _str(json['mode']),
    amount: asDouble(json['amount']),
  );
}

/// One printed row of the items table: every selected LR sharing a billed
/// amount collapses into a single line whose qty is the LR count.
class InvoiceLine {
  final String id;
  final int srNo;
  final String title;
  final String hsnSac;
  final double qty;
  final String uom;
  final double rate;
  final double amount;
  final List<InvoiceLineLr> lrs;

  const InvoiceLine({
    required this.id,
    this.srNo = 0,
    this.title = '',
    this.hsnSac = '',
    this.qty = 0,
    this.uom = '',
    this.rate = 0,
    this.amount = 0,
    this.lrs = const [],
  });

  /// qty without noise digits: 3.00 -> "3", 2.50 -> "2.5".
  String get qtyText => pctText(qty);

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    id: _str(json['id']),
    srNo: asInt(json['sr_no']),
    title: _str(json['title']),
    hsnSac: _str(json['hsn_sac']),
    qty: asDouble(json['qty']),
    uom: _str(json['uom']),
    rate: asDouble(json['rate']),
    amount: asDouble(json['amount']),
    lrs: _maps(json['lrs']).map(InvoiceLineLr.fromJson).toList(),
  );
}

/// A sales invoice header plus, where the endpoint includes them, its lines.
/// `GET /invoices` returns headers only ([lines] empty); `GET /invoices/:id`,
/// the create response and the cancel response carry the full document.
class Invoice {
  final String id;
  final String number;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String customerId;

  /// From the `customer` include on list/detail; '' when the association was
  /// not requested. What the document prints is [billToName], the snapshot.
  final String customerName;

  final String billToName;
  final String billToAddress;
  final String billToGstin;
  final String billToState;
  final String billToStateCode;
  final String shipToName;
  final String shipToAddress;
  final String shipToGstin;
  final String shipToState;
  final String shipToStateCode;

  final String vendorCode;
  final String referenceNo;
  final String otherReference;
  final String placeOfSupply;
  final String placeOfSupplyCode;

  final bool isTaxInvoice;

  /// INTRA | INTER | NONE.
  final String taxMode;
  final String hsnSac;
  final String serviceMode;

  final double subTotal;
  // Rate AND amount are persisted per invoice so a document can be reprinted
  // verbatim after a statutory rate change. Null on the heads that do not
  // apply to [taxMode].
  final double? cgstRate;
  final double? cgstAmount;
  final double? sgstRate;
  final double? sgstAmount;
  final double? igstRate;
  final double? igstAmount;
  final double total;

  final String amountInWords;
  final String notes;

  /// ISSUED | CANCELLED.
  final String status;
  final int version;

  final String regionId;
  final String regionName;
  final String regionCode;

  final List<InvoiceLine> lines;

  const Invoice({
    required this.id,
    required this.number,
    required this.invoiceDate,
    this.dueDate,
    this.customerId = '',
    this.customerName = '',
    this.billToName = '',
    this.billToAddress = '',
    this.billToGstin = '',
    this.billToState = '',
    this.billToStateCode = '',
    this.shipToName = '',
    this.shipToAddress = '',
    this.shipToGstin = '',
    this.shipToState = '',
    this.shipToStateCode = '',
    this.vendorCode = '',
    this.referenceNo = '',
    this.otherReference = '',
    this.placeOfSupply = '',
    this.placeOfSupplyCode = '',
    this.isTaxInvoice = true,
    this.taxMode = invoiceTaxModeIntra,
    this.hsnSac = '',
    this.serviceMode = '',
    this.subTotal = 0,
    this.cgstRate,
    this.cgstAmount,
    this.sgstRate,
    this.sgstAmount,
    this.igstRate,
    this.igstAmount,
    this.total = 0,
    this.amountInWords = '',
    this.notes = '',
    this.status = invoiceStatusIssued,
    this.version = 0,
    this.regionId = '',
    this.regionName = '',
    this.regionCode = '',
    this.lines = const [],
  });

  bool get isCancelled => status == invoiceStatusCancelled;
  bool get isIssued => status == invoiceStatusIssued;

  /// The tax heading the UI prints, derived from the STORED tax mode and the
  /// STORED rates — never recomputed from [subTotal] and [total], which would
  /// restate a historical invoice after a rate change.
  String get taxLabel {
    switch (taxMode) {
      case invoiceTaxModeIntra:
        return 'CGST ${pctText(cgstRate ?? 0)}% + '
            'SGST ${pctText(sgstRate ?? 0)}%';
      case invoiceTaxModeInter:
        return 'IGST ${pctText(igstRate ?? 0)}%';
      default:
        return 'No GST';
    }
  }

  /// Sum of the stored tax amounts — read, not derived from the totals.
  double get taxAmount =>
      (cgstAmount ?? 0) + (sgstAmount ?? 0) + (igstAmount ?? 0);

  /// How many LRs this invoice bills. 0 on a list row, which carries no lines.
  int get lrCount => lines.fold(0, (sum, line) => sum + line.lrs.length);

  /// Every LR on the document, flattened in printed order.
  List<InvoiceLineLr> get allLrs => [for (final line in lines) ...line.lrs];

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final customer = (json['customer'] as Map?)?.cast<String, dynamic>();
    final region = (json['region'] as Map?)?.cast<String, dynamic>();
    final taxMode = _str(json['tax_mode']);
    final status = _str(json['status']);
    return Invoice(
      id: _str(json['id']),
      number: _str(json['number']),
      invoiceDate: _dateOrNull(json['invoice_date']) ?? DateTime.now(),
      dueDate: _dateOrNull(json['due_date']),
      customerId: _str(json['customer_id']),
      customerName: _str(customer?['name']),
      billToName: _str(json['bill_to_name']),
      billToAddress: _str(json['bill_to_address']),
      billToGstin: _str(json['bill_to_gstin']),
      billToState: _str(json['bill_to_state']),
      billToStateCode: _str(json['bill_to_state_code']),
      shipToName: _str(json['ship_to_name']),
      shipToAddress: _str(json['ship_to_address']),
      shipToGstin: _str(json['ship_to_gstin']),
      shipToState: _str(json['ship_to_state']),
      shipToStateCode: _str(json['ship_to_state_code']),
      vendorCode: _str(json['vendor_code']),
      referenceNo: _str(json['reference_no']),
      otherReference: _str(json['other_reference']),
      placeOfSupply: _str(json['place_of_supply']),
      placeOfSupplyCode: _str(json['place_of_supply_code']),
      // The column is NOT NULL with a true default, so only an explicit false
      // means the untaxed layout.
      isTaxInvoice: json['is_tax_invoice'] != false,
      taxMode: taxMode.isEmpty ? invoiceTaxModeIntra : taxMode,
      hsnSac: _str(json['hsn_sac']),
      serviceMode: _str(json['service_mode']),
      subTotal: asDouble(json['sub_total']),
      cgstRate: asDoubleOrNull(json['cgst_rate']),
      cgstAmount: asDoubleOrNull(json['cgst_amount']),
      sgstRate: asDoubleOrNull(json['sgst_rate']),
      sgstAmount: asDoubleOrNull(json['sgst_amount']),
      igstRate: asDoubleOrNull(json['igst_rate']),
      igstAmount: asDoubleOrNull(json['igst_amount']),
      total: asDouble(json['total']),
      amountInWords: _str(json['amount_in_words']),
      notes: _str(json['notes']),
      status: status.isEmpty ? invoiceStatusIssued : status,
      version: asInt(json['version']),
      regionId: _str(json['region_id']),
      regionName: _str(region?['name']),
      regionCode: _str(region?['short_code']),
      lines: _maps(json['lines']).map(InvoiceLine.fromJson).toList(),
    );
  }
}

/// The company block on the letterhead.
class InvoiceCompanySettings {
  final String name;
  final List<String> addressLines;
  final String gstin;
  final String state;
  final String email;
  final String website;

  /// Signature caption ("For Vistar Logitek Pvt. Ltd.") — the short trading
  /// name, which is deliberately not [name].
  final String signFor;

  const InvoiceCompanySettings({
    this.name = '',
    this.addressLines = const [],
    this.gstin = '',
    this.state = '',
    this.email = '',
    this.website = '',
    this.signFor = '',
  });

  factory InvoiceCompanySettings.fromJson(Map<String, dynamic> json) =>
      InvoiceCompanySettings(
        name: _str(json['name']),
        addressLines: _strings(json['address_lines']),
        gstin: _str(json['gstin']),
        state: _str(json['state']),
        email: _str(json['email']),
        website: _str(json['website']),
        signFor: _str(json['sign_for']),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'address_lines': addressLines,
    'gstin': gstin,
    'state': state,
    'email': email,
    'website': website,
    'sign_for': signFor,
  };

  InvoiceCompanySettings copyWith({
    String? name,
    List<String>? addressLines,
    String? gstin,
    String? state,
    String? email,
    String? website,
    String? signFor,
  }) => InvoiceCompanySettings(
    name: name ?? this.name,
    addressLines: addressLines ?? this.addressLines,
    gstin: gstin ?? this.gstin,
    state: state ?? this.state,
    email: email ?? this.email,
    website: website ?? this.website,
    signFor: signFor ?? this.signFor,
  );
}

/// The bank block. It holds the company's account number, which is why writing
/// settings is admin-only — never log or cache it.
class InvoiceBankSettings {
  final String name;
  final String accountNo;
  final String branchIfsc;

  const InvoiceBankSettings({
    this.name = '',
    this.accountNo = '',
    this.branchIfsc = '',
  });

  factory InvoiceBankSettings.fromJson(Map<String, dynamic> json) =>
      InvoiceBankSettings(
        name: _str(json['name']),
        accountNo: _str(json['account_no']),
        branchIfsc: _str(json['branch_ifsc']),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'account_no': accountNo,
    'branch_ifsc': branchIfsc,
  };

  InvoiceBankSettings copyWith({
    String? name,
    String? accountNo,
    String? branchIfsc,
  }) => InvoiceBankSettings(
    name: name ?? this.name,
    accountNo: accountNo ?? this.accountNo,
    branchIfsc: branchIfsc ?? this.branchIfsc,
  );
}

/// The INVOICE_SETTINGS blob: letterhead, bank, declaration and the defaults
/// the create form seeds itself from.
///
/// `PUT /invoices/settings` rejects UNKNOWN keys — the server turns off
/// stripUnknown on purpose, so a misspelt key is an error rather than a
/// silently dropped logo. [toJson] therefore emits exactly the keys the Joi
/// schema declares and nothing else.
class InvoiceSettings {
  final InvoiceCompanySettings company;
  final InvoiceBankSettings bank;
  final List<String> declaration;
  final String jurisdictionText;
  final String computerGeneratedText;

  /// The SELLER's GSTIN. Its first two digits decide CGST+SGST vs IGST, so no
  /// tax invoice can be issued without it — the server 400s a save carrying
  /// neither this nor `company.gstin`.
  final String sellerGstin;

  /// Default GST percentage. Null means "let the server decide", and the key is
  /// then omitted from the payload: the Joi field is a plain number and rejects
  /// an explicit null.
  final double? gstRate;
  final String defaultHsnSac;
  final String defaultServiceMode;
  final String defaultLineTitle;

  /// storage.service object keys, not URLs — the renderer loads the bytes
  /// server-side, so the images never have to be publicly reachable.
  final String logoKey;
  final String signatureKey;

  const InvoiceSettings({
    this.company = const InvoiceCompanySettings(),
    this.bank = const InvoiceBankSettings(),
    this.declaration = const [],
    this.jurisdictionText = '',
    this.computerGeneratedText = '',
    this.sellerGstin = '',
    this.gstRate,
    this.defaultHsnSac = '',
    this.defaultServiceMode = '',
    this.defaultLineTitle = '',
    this.logoKey = '',
    this.signatureKey = '',
  });

  /// The GSTIN the server will actually read, with the same fallback it uses.
  String get effectiveSellerGstin =>
      sellerGstin.isNotEmpty ? sellerGstin : company.gstin;

  /// A save without a seller GSTIN is rejected; surface it in the form first.
  bool get hasSellerGstin => effectiveSellerGstin.isNotEmpty;

  factory InvoiceSettings.fromJson(Map<String, dynamic> json) =>
      InvoiceSettings(
        company: InvoiceCompanySettings.fromJson(
          (json['company'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        bank: InvoiceBankSettings.fromJson(
          (json['bank'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        declaration: _strings(json['declaration']),
        jurisdictionText: _str(json['jurisdiction_text']),
        computerGeneratedText: _str(json['computer_generated_text']),
        sellerGstin: _str(json['seller_gstin']),
        gstRate: asDoubleOrNull(json['gst_rate']),
        defaultHsnSac: _str(json['default_hsn_sac']),
        defaultServiceMode: _str(json['default_service_mode']),
        defaultLineTitle: _str(json['default_line_title']),
        logoKey: _str(json['logo_key']),
        signatureKey: _str(json['signature_key']),
      );

  Map<String, dynamic> toJson() => {
    'company': company.toJson(),
    'bank': bank.toJson(),
    'declaration': declaration,
    'jurisdiction_text': jurisdictionText,
    'computer_generated_text': computerGeneratedText,
    'seller_gstin': sellerGstin,
    if (gstRate != null) 'gst_rate': gstRate,
    'default_hsn_sac': defaultHsnSac,
    'default_service_mode': defaultServiceMode,
    'default_line_title': defaultLineTitle,
    'logo_key': logoKey,
    'signature_key': signatureKey,
  };

  InvoiceSettings copyWith({
    InvoiceCompanySettings? company,
    InvoiceBankSettings? bank,
    List<String>? declaration,
    String? jurisdictionText,
    String? computerGeneratedText,
    String? sellerGstin,
    double? gstRate,
    bool clearGstRate = false,
    String? defaultHsnSac,
    String? defaultServiceMode,
    String? defaultLineTitle,
    String? logoKey,
    String? signatureKey,
  }) => InvoiceSettings(
    company: company ?? this.company,
    bank: bank ?? this.bank,
    declaration: declaration ?? this.declaration,
    jurisdictionText: jurisdictionText ?? this.jurisdictionText,
    computerGeneratedText: computerGeneratedText ?? this.computerGeneratedText,
    sellerGstin: sellerGstin ?? this.sellerGstin,
    gstRate: clearGstRate ? null : (gstRate ?? this.gstRate),
    defaultHsnSac: defaultHsnSac ?? this.defaultHsnSac,
    defaultServiceMode: defaultServiceMode ?? this.defaultServiceMode,
    defaultLineTitle: defaultLineTitle ?? this.defaultLineTitle,
    logoKey: logoKey ?? this.logoKey,
    signatureKey: signatureKey ?? this.signatureKey,
  );
}
