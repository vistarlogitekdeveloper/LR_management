class SystemConfig {
  // LR numbering
  final String lrPrefix;
  final String lrFormat;
  final int nextLrNumber;

  // LR print format
  final String companyName;
  final String companyTagline;
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
    this.lrFormat = '{prefix}/{YY}/{MM}/{seq:05d}',
    this.nextLrNumber = 1,
    this.companyName = 'Vistar Logitek Pvt Ltd',
    this.companyTagline = 'Transport Documentation · Dispatch · Billing',
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
    String? companyName,
    String? companyTagline,
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
      companyName: companyName ?? this.companyName,
      companyTagline: companyTagline ?? this.companyTagline,
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
