class Transporter {
  final String id;
  final String name;
  final String pan;
  final String tds; // 'Yes' / 'No' (maps to backend tds_applicable)
  // Bank / payment details — persisted in the backend `bank_account` JSONB.
  final String bankName;
  final String accountHolder;
  final String accountNo;
  final String ifsc;
  // Uploaded blank cheque / passbook photo (stored under bank_account too).
  final String chequeFileKey;
  final String chequeFileName;
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
    this.bankName = '',
    this.accountHolder = '',
    this.accountNo = '',
    this.ifsc = '',
    this.chequeFileKey = '',
    this.chequeFileName = '',
    this.ocrDone = false,
    this.ocrIfsc = '',
    this.ocrAccountNo = '',
    this.version = 0,
  });

  bool get tdsApplicable => tds.toLowerCase() == 'yes';
  bool get hasDocument => chequeFileKey.isNotEmpty;

  static String _normIfsc(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'\s'), '');
  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

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
      ocrDone &&
      (ifscMatchesOcr() == false || accountMatchesOcr() == false);

  factory Transporter.fromJson(Map<String, dynamic> json) {
    final bank = (json['bank_account'] is Map)
        ? (json['bank_account'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return Transporter(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      pan: (json['pan'] as String?) ?? '',
      tds: (json['tds_applicable'] as bool?) == true ? 'Yes' : 'No',
      bankName: (bank['bank_name'] as String?) ?? '',
      accountHolder: (bank['account_holder'] as String?) ?? '',
      accountNo: (bank['account_no'] as String?) ?? '',
      ifsc: (bank['ifsc'] as String?) ?? '',
      chequeFileKey: (bank['cheque_file_key'] as String?) ?? '',
      chequeFileName: (bank['cheque_file_name'] as String?) ?? '',
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
    String? bankName,
    String? accountHolder,
    String? accountNo,
    String? ifsc,
    String? chequeFileKey,
    String? chequeFileName,
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
      bankName: bankName ?? this.bankName,
      accountHolder: accountHolder ?? this.accountHolder,
      accountNo: accountNo ?? this.accountNo,
      ifsc: ifsc ?? this.ifsc,
      chequeFileKey: chequeFileKey ?? this.chequeFileKey,
      chequeFileName: chequeFileName ?? this.chequeFileName,
      ocrDone: ocrDone ?? this.ocrDone,
      ocrIfsc: ocrIfsc ?? this.ocrIfsc,
      ocrAccountNo: ocrAccountNo ?? this.ocrAccountNo,
      version: version ?? this.version,
    );
  }
}
