import '../../core/utils/json_parse.dart';

/// Share of the transporter freight released up front as an advance when
/// nothing more specific is configured. Historically this was hardcoded at 90%
/// across the app; it is now a per-transporter default that each LR copies and
/// may override, so this constant is only the fallback for a transporter (or a
/// legacy LR) that carries no explicit figure.
///
/// Must stay in step with the backend: the `advance_percent` column default in
/// migration 088 and the `== null ? 90` fallbacks in lrController.markAdvancePaid
/// and lrPaymentEmail.service.
const double kDefaultAdvancePercent = 90;

class Transporter {
  final String id;
  final String name;
  final String pan;
  final String tds; // 'Yes' / 'No' (maps to backend tds_applicable)
  /// Default share of the transporter freight released up front as an advance.
  /// Copied onto each new LR for this transporter (which may then override it
  /// for that one LR). 90 unless the partner negotiated something else.
  final double advancePercent;
  // Bank / payment details — persisted in the backend `bank_account` JSONB.
  final String bankName;
  final String accountHolder;
  final String accountNo;
  final String ifsc;
  // Uploaded blank cheque / passbook photo (stored under bank_account too).
  final String chequeFileKey;
  final String chequeFileName;
  // Uploaded TDS attachment (certificate / declaration), also under bank_account.
  final String tdsFileKey;
  final String tdsFileName;
  // OCR readout of the uploaded cheque (raw values; the match is computed live).
  final bool ocrDone;
  final String ocrIfsc;
  final String ocrAccountNo;
  final int version;

  const Transporter({
    required this.id,
    required this.name,
    required this.pan,
    required this.tds,
    this.advancePercent = kDefaultAdvancePercent,
    this.bankName = '',
    this.accountHolder = '',
    this.accountNo = '',
    this.ifsc = '',
    this.chequeFileKey = '',
    this.chequeFileName = '',
    this.tdsFileKey = '',
    this.tdsFileName = '',
    this.ocrDone = false,
    this.ocrIfsc = '',
    this.ocrAccountNo = '',
    this.version = 0,
  });

  bool get tdsApplicable => tds.toLowerCase() == 'yes';
  bool get hasDocument => chequeFileKey.isNotEmpty;
  bool get hasTdsDocument => tdsFileKey.isNotEmpty;

  // Built once, not per comparison — these run for every transporter row.
  static final _whitespace = RegExp(r'\s');
  static final _nonDigits = RegExp(r'[^0-9]');

  static String _normIfsc(String s) =>
      s.toUpperCase().replaceAll(_whitespace, '');
  static String _digits(String s) => s.replaceAll(_nonDigits, '');

  /// Does the OCR'd cheque IFSC match the entered one? `null` = not checked
  /// (no cheque OCR yet, or nothing entered to compare). Pass [entered] to
  /// compare a live form value instead of the saved one.
  bool? ifscMatchesOcr([String? entered]) {
    if (!ocrDone || ocrIfsc.isEmpty) return null;
    final e = _normIfsc(entered ?? ifsc);
    if (e.isEmpty) return null;
    return _normIfsc(ocrIfsc) == e;
  }

  bool? accountMatchesOcr([String? entered]) {
    if (!ocrDone || ocrAccountNo.isEmpty) return null;
    final e = _digits(entered ?? accountNo);
    // Real account numbers are >= 9 digits; below that a containment check
    // would yield false positives, so leave it unverified.
    if (e.length < 9) return null;
    final o = _digits(ocrAccountNo);
    if (o.isEmpty) return null;
    // Exact, or the entered number appears within the (often longer, MICR-line)
    // OCR run. Not the reverse — a short OCR fragment must not "match".
    return o == e || o.contains(e);
  }

  /// True when the cheque was read and a checked field disagrees with entry.
  bool get ocrHasMismatch =>
      ocrDone && (ifscMatchesOcr() == false || accountMatchesOcr() == false);

  factory Transporter.fromJson(Map<String, dynamic> json) {
    final bank = (json['bank_account'] is Map)
        ? (json['bank_account'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return Transporter(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      pan: (json['pan'] as String?) ?? '',
      tds: (json['tds_applicable'] as bool?) == true ? 'Yes' : 'No',
      // NUMERIC comes back as a string ("75.00"); asDoubleOrNull handles both
      // that and a real number. Falls back to 90 only when genuinely absent —
      // an explicit 0 ("no advance") must survive, which `?? ` preserves and a
      // truthiness check would not.
      advancePercent:
          asDoubleOrNull(json['advance_percent']) ?? kDefaultAdvancePercent,
      bankName: (bank['bank_name'] as String?) ?? '',
      accountHolder: (bank['account_holder'] as String?) ?? '',
      accountNo: (bank['account_no'] as String?) ?? '',
      ifsc: (bank['ifsc'] as String?) ?? '',
      chequeFileKey: (bank['cheque_file_key'] as String?) ?? '',
      chequeFileName: (bank['cheque_file_name'] as String?) ?? '',
      tdsFileKey: (bank['tds_file_key'] as String?) ?? '',
      tdsFileName: (bank['tds_file_name'] as String?) ?? '',
      ocrDone: (bank['ocr_done'] as bool?) ?? false,
      ocrIfsc: (bank['ocr_ifsc'] as String?) ?? '',
      ocrAccountNo: (bank['ocr_account_no'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (pan.isNotEmpty) 'pan': pan,
    'tds_applicable': tdsApplicable,
    'advance_percent': advancePercent,
    // Only the user-editable bank fields are sent — always (so clearing a
    // field sticks). On PATCH the backend MERGES this onto the stored
    // bank_account, preserving the cheque key + OCR readout set out-of-band
    // by the document upload.
    'bank_account': {
      'bank_name': bankName,
      'account_holder': accountHolder,
      'account_no': accountNo,
      'ifsc': ifsc,
    },
  };

  Transporter copyWith({
    String? name,
    String? pan,
    String? tds,
    double? advancePercent,
    String? bankName,
    String? accountHolder,
    String? accountNo,
    String? ifsc,
    String? chequeFileKey,
    String? chequeFileName,
    String? tdsFileKey,
    String? tdsFileName,
    bool? ocrDone,
    String? ocrIfsc,
    String? ocrAccountNo,
    int? version,
  }) {
    return Transporter(
      id: id,
      name: name ?? this.name,
      pan: pan ?? this.pan,
      tds: tds ?? this.tds,
      advancePercent: advancePercent ?? this.advancePercent,
      bankName: bankName ?? this.bankName,
      accountHolder: accountHolder ?? this.accountHolder,
      accountNo: accountNo ?? this.accountNo,
      ifsc: ifsc ?? this.ifsc,
      chequeFileKey: chequeFileKey ?? this.chequeFileKey,
      chequeFileName: chequeFileName ?? this.chequeFileName,
      tdsFileKey: tdsFileKey ?? this.tdsFileKey,
      tdsFileName: tdsFileName ?? this.tdsFileName,
      ocrDone: ocrDone ?? this.ocrDone,
      ocrIfsc: ocrIfsc ?? this.ocrIfsc,
      ocrAccountNo: ocrAccountNo ?? this.ocrAccountNo,
      version: version ?? this.version,
    );
  }
}
