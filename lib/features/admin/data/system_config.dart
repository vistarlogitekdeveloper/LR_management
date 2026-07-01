class SystemConfig {
  // LR numbering (per-region: each region has its own numbering row, plus an
  // optional tenant-wide fallback row used by super admins for region-less LRs).
  final String lrPrefix;
  final String lrFormat;
  final int nextLrNumber;

  /// The region this numbering row belongs to. `null` = the tenant-wide
  /// fallback row. Sent back on save so the correct row is edited.
  final String? lrRegionId;

  /// Region short code (e.g. `PUN`) — rendered by the `{REGION}` token.
  final String lrRegionCode;

  /// Region display name (e.g. `Pune`) — shown as context on the screen.
  final String lrRegionName;

  /// Reset cadence: `FINANCIAL_YEAR`, `YEARLY`, `MONTHLY`, or `NEVER`.
  final String lrResetPeriod;

  // LR print format
  final String companyName;
  final String companyTagline;
  final String companyAddress;
  final String companyGstin;
  final String termsText;
  final String footerText;
  final bool showVistarMargin;
  final bool showMathadi;
  final bool showInsurance;
  final bool showEwb;

  // Security / system (local defaults — no dedicated backend columns yet)
  final bool dailyBackup;
  final String backupTime;
  final bool auditTrail;
  final String passwordPolicy;

  const SystemConfig({
    this.lrPrefix = 'LR',
    this.lrFormat = '{prefix}/{REGION}/{FY}/{seq:05d}',
    this.nextLrNumber = 1,
    this.lrRegionId,
    this.lrRegionCode = '',
    this.lrRegionName = '',
    this.lrResetPeriod = 'FINANCIAL_YEAR',
    this.companyName = 'Vistar Logitek Private Limited',
    this.companyTagline = 'Warehousing, Transportation & Contracts Logistics',
    this.companyAddress =
        'Office No. 302, 3rd Floor, MSR Capital Building, Samrat Chowk, Morwadi, Pimpri, Pune 411018.',
    this.companyGstin = 'MH 27AAECV9694A1ZZ',
    this.termsText =
        'All disputes subject to Pune jurisdiction. Goods carried at owner\'s risk. Insurance to be arranged by consignor unless otherwise agreed.',
    this.footerText = 'For Vistar Logitek Pvt Ltd',
    this.showVistarMargin = false,
    this.showMathadi = true,
    this.showInsurance = true,
    this.showEwb = true,
    this.dailyBackup = true,
    this.backupTime = '02:00',
    this.auditTrail = true,
    this.passwordPolicy = 'Min 10 chars',
  });

  SystemConfig copyWith({
    String? lrPrefix,
    String? lrFormat,
    int? nextLrNumber,
    String? lrRegionId,
    String? lrRegionCode,
    String? lrRegionName,
    String? lrResetPeriod,
    String? companyName,
    String? companyTagline,
    String? companyAddress,
    String? companyGstin,
    String? termsText,
    String? footerText,
    bool? showVistarMargin,
    bool? showMathadi,
    bool? showInsurance,
    bool? showEwb,
    bool? dailyBackup,
    String? backupTime,
    bool? auditTrail,
    String? passwordPolicy,
  }) {
    return SystemConfig(
      lrPrefix: lrPrefix ?? this.lrPrefix,
      lrFormat: lrFormat ?? this.lrFormat,
      nextLrNumber: nextLrNumber ?? this.nextLrNumber,
      lrRegionId: lrRegionId ?? this.lrRegionId,
      lrRegionCode: lrRegionCode ?? this.lrRegionCode,
      lrRegionName: lrRegionName ?? this.lrRegionName,
      lrResetPeriod: lrResetPeriod ?? this.lrResetPeriod,
      companyName: companyName ?? this.companyName,
      companyTagline: companyTagline ?? this.companyTagline,
      companyAddress: companyAddress ?? this.companyAddress,
      companyGstin: companyGstin ?? this.companyGstin,
      termsText: termsText ?? this.termsText,
      footerText: footerText ?? this.footerText,
      showVistarMargin: showVistarMargin ?? this.showVistarMargin,
      showMathadi: showMathadi ?? this.showMathadi,
      showInsurance: showInsurance ?? this.showInsurance,
      showEwb: showEwb ?? this.showEwb,
      dailyBackup: dailyBackup ?? this.dailyBackup,
      backupTime: backupTime ?? this.backupTime,
      auditTrail: auditTrail ?? this.auditTrail,
      passwordPolicy: passwordPolicy ?? this.passwordPolicy,
    );
  }
}
