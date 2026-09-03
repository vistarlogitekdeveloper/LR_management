/// Results of the two scan-to-autofill endpoints.
///
///   POST /transporters/scan-cheque  -> [ScannedCheque]
///   POST /lrs/scan                  -> [ScannedLrDraft]
///
/// Both carry a `review` map alongside the values: per-field confidence and a
/// `needsReview` flag. Keeping those apart from the values is the point — a
/// prefilled field nobody looked at is worse than an empty one, because the
/// empty one gets typed correctly and the wrong one gets saved. The UI must
/// fill AND flag.
library;

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

class ScanFieldReview {
  const ScanFieldReview({
    required this.confidence,
    required this.needsReview,
    this.value,
    this.source,
    this.reason,
    this.note,
    this.verifiedBy = const [],
    this.alternatives = const [],
  });

  /// 0..1. Not a probability — a score combining OCR confidence with whatever
  /// structural checks the field supports (a GSTIN has a check digit; a bank
  /// account number has nothing).
  final double confidence;
  final bool needsReview;
  final dynamic value;

  /// 'label:IFSC Code', 'shape', 'geometry', 'master-lookup'. Worth showing on
  /// a flagged field: it tells the user where to look to check it.
  final String? source;
  final String? reason;

  /// Set when the server repaired what it read (e.g. an IFSC whose mandatory
  /// '0' was misread as 'O'), so the change is disclosed rather than hidden.
  final String? note;

  /// Checks this value PASSED — 'checksum', 'tax-arithmetic',
  /// 'amount-in-words'. Lets the UI say why a value is trusted.
  final List<String> verifiedBy;
  final List<Map<String, dynamic>> alternatives;

  bool get isVerified => verifiedBy.isNotEmpty;

  factory ScanFieldReview.fromJson(Map<String, dynamic> json) {
    final v = json['verifiedBy'];
    final a = json['alternatives'];
    return ScanFieldReview(
      confidence: _toDouble(json['confidence']) ?? 0,
      needsReview: json['needsReview'] as bool? ?? false,
      value: json['value'],
      source: json['source']?.toString(),
      reason: json['reason']?.toString(),
      note: json['note']?.toString(),
      verifiedBy: v is List ? v.map((e) => e.toString()).toList() : const [],
      alternatives: a is List
          ? a.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
          : const [],
    );
  }
}

class ScanWarning {
  const ScanWarning({
    required this.code,
    required this.message,
    this.fields = const [],
  });

  final String code;
  final String message;
  final List<String> fields;

  /// The photo itself is the problem — a retake fixes more than correcting
  /// fields by hand.
  bool get isPhotoQuality => const {
        'BLURRED_IMAGE',
        'LOW_CONTRAST_IMAGE',
        'LOW_RESOLUTION_IMAGE',
        'NO_TEXT_DETECTED',
        'PDF_HAS_NO_TEXT_LAYER',
      }.contains(code);

  /// Must be read, not just glanced at. VERIFY_ACCOUNT_NUMBER is here because
  /// a bank account number cannot be validated offline at all and a wrong one
  /// pays a stranger; GOODS_VALUE_NOT_FREIGHT because confusing the two
  /// inflates a transporter payout by an order of magnitude.
  bool get isImportant => const {
        'VERIFY_ACCOUNT_NUMBER',
        'GOODS_VALUE_NOT_FREIGHT',
        'ACCOUNT_WITHOUT_IFSC',
      }.contains(code);

  factory ScanWarning.fromJson(Map<String, dynamic> json) {
    final f = json['fields'];
    return ScanWarning(
      code: json['code']?.toString() ?? 'WARNING',
      message: json['message']?.toString() ?? '',
      fields: f is List ? f.map((e) => e.toString()).toList() : const [],
    );
  }
}

Map<String, ScanFieldReview> _reviewFrom(dynamic raw) {
  final out = <String, ScanFieldReview>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      if (v is Map) {
        out[k.toString()] = ScanFieldReview.fromJson(v.cast<String, dynamic>());
      }
    });
  }
  return out;
}

List<ScanWarning> _warningsFrom(dynamic raw) => raw is List
    ? raw
        .whereType<Map>()
        .map((w) => ScanWarning.fromJson(w.cast<String, dynamic>()))
        .toList()
    : const [];

// ---------------------------------------------------------------------------
// POST /transporters/scan-cheque
// ---------------------------------------------------------------------------

/// Bank details read off a cancelled cheque or passbook.
///
/// The foreground counterpart to the background OCR that annotates a saved
/// transporter after its document is uploaded. That runs too late to help with
/// data entry: by then the account number has already been typed, and it is
/// the field most worth not typing — 9 to 18 digits with no checksum, no
/// format rule and no directory to verify against.
class ScannedCheque {
  const ScannedCheque({
    required this.readable,
    this.scanId,
    this.ifsc,
    this.accountNo,
    this.bankName,
    this.accountHolder,
    this.branch,
    this.review = const {},
    this.warnings = const [],
    this.pageConfidence,
  });

  final bool readable;
  final String? scanId;
  final String? ifsc;
  final String? accountNo;
  final String? bankName;
  final String? accountHolder;
  final String? branch;
  final Map<String, ScanFieldReview> review;
  final List<ScanWarning> warnings;
  final double? pageConfidence;

  bool get hasAnything =>
      (ifsc ?? accountNo ?? bankName ?? accountHolder ?? branch) != null;

  ScanWarning? warningWithCode(String code) {
    for (final w in warnings) {
      if (w.code == code) return w;
    }
    return null;
  }

  /// Review entries are keyed by the API's canonical field names, which differ
  /// from the bank_account keys the values come back under.
  ScanFieldReview? reviewFor(String bankAccountKey) => review[const {
        'ifsc': 'ifscCode',
        'account_no': 'accountNo',
        'bank_name': 'bankName',
        'account_holder': 'accountHolder',
        'branch': 'branch',
      }[bankAccountKey]];

  factory ScannedCheque.fromJson(Map<String, dynamic> json) {
    final bank = json['bankAccount'] is Map
        ? (json['bankAccount'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    String? s(String k) {
      final v = bank[k];
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    return ScannedCheque(
      readable: json['readable'] as bool? ?? false,
      scanId: json['scanId']?.toString(),
      ifsc: s('ifsc'),
      accountNo: s('account_no'),
      bankName: s('bank_name'),
      accountHolder: s('account_holder'),
      branch: s('branch'),
      review: _reviewFrom(json['review']),
      warnings: _warningsFrom(json['warnings']),
      pageConfidence: _toDouble(json['confidence']),
    );
  }
}

// ---------------------------------------------------------------------------
// POST /lrs/scan
// ---------------------------------------------------------------------------

/// A draft LR read from a consignor invoice, e-way bill or consignment note.
///
/// Unlike the gate module's draft, this one is NOT directly submittable: an LR
/// needs `delivery_type_id` and `pay_type_id`, which appear on no supplier
/// document. [missingRequired] says which, so the UI can be honest rather than
/// implying the draft can be saved as-is.
class ScannedLrDraft {
  const ScannedLrDraft({
    required this.readable,
    this.scanId,
    this.profile,
    this.draft = const {},
    this.review = const {},
    this.resolved = const {},
    this.missingRequired = const [],
    this.warnings = const [],
    this.pageConfidence,
  });

  final bool readable;
  final String? scanId;
  final String? profile;

  /// Values keyed by LR create-body names (lr_date, consignor_id, freight…).
  final Map<String, dynamic> draft;
  final Map<String, ScanFieldReview> review;

  /// Master-resolution detail per entity: consignor, consignee, vehicle,
  /// transporter, route, payType.
  final Map<String, ScanResolution> resolved;

  /// Required LR fields the document cannot supply.
  final List<String> missingRequired;
  final List<ScanWarning> warnings;
  final double? pageConfidence;

  bool get hasDraft => draft.isNotEmpty;

  /// Header values, excluding the nested invoice item list.
  Map<String, dynamic> get headerFields {
    final out = <String, dynamic>{};
    draft.forEach((k, v) {
      if (k != 'invoice_items') out[k] = v;
    });
    return out;
  }

  List<Map<String, dynamic>> get invoiceItems {
    final raw = draft['invoice_items'];
    return raw is List
        ? raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const [];
  }

  ScanWarning? warningWithCode(String code) {
    for (final w in warnings) {
      if (w.code == code) return w;
    }
    return null;
  }

  /// True when the scan put a goods value on the invoice item rather than into
  /// freight. Worth surfacing prominently: freight is negotiated with the
  /// transporter and is not what the invoice says.
  bool get goodsValueNotFreight =>
      warningWithCode('GOODS_VALUE_NOT_FREIGHT') != null;

  factory ScannedLrDraft.fromJson(Map<String, dynamic> json) {
    final resolved = <String, ScanResolution>{};
    final rawResolved = json['resolved'];
    if (rawResolved is Map) {
      rawResolved.forEach((k, v) {
        if (v is Map) {
          resolved[k.toString()] =
              ScanResolution.fromJson(v.cast<String, dynamic>());
        }
      });
    }
    final missing = json['missingRequired'];
    return ScannedLrDraft(
      readable: json['readable'] as bool? ?? false,
      scanId: json['scanId']?.toString(),
      profile: json['profile']?.toString(),
      draft: json['draft'] is Map
          ? (json['draft'] as Map).cast<String, dynamic>()
          : const {},
      review: _reviewFrom(json['review']),
      resolved: resolved,
      missingRequired:
          missing is List ? missing.map((e) => e.toString()).toList() : const [],
      warnings: _warningsFrom(json['warnings']),
      pageConfidence: _toDouble(json['confidence']),
    );
  }
}

/// How a scanned name/number resolved against a master table.
///
/// [id] is null when nothing matched clearly. The server refuses to guess on a
/// tie — the live masters contain duplicate and near-duplicate rows, and
/// booking a consignment against the wrong consignor puts it on the wrong
/// customer's account — so [candidates] is what the user picks from.
class ScanResolution {
  const ScanResolution({
    this.id,
    this.name,
    this.city,
    required this.confidence,
    this.matchedOn,
    this.candidates = const [],
  });

  final String? id;
  final String? name;
  final String? city;
  final double confidence;
  final String? matchedOn;
  final List<Map<String, dynamic>> candidates;

  bool get isResolved => (id ?? '').isNotEmpty;

  factory ScanResolution.fromJson(Map<String, dynamic> json) {
    final c = json['candidates'];
    final id = json['id']?.toString() ?? '';
    return ScanResolution(
      id: id.isEmpty ? null : id,
      name: json['name']?.toString(),
      city: json['city']?.toString(),
      confidence: _toDouble(json['confidence']) ?? 0,
      matchedOn: json['matchedOn']?.toString(),
      candidates: c is List
          ? c.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
          : const [],
    );
  }
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
