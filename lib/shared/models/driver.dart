class Driver {
  final String id;
  final String name;
  final String mobile;
  final String licenseNo;
  final String? licenseExpiry; // YYYY-MM-DD
  final String address;

  /// 12-digit Aadhaar, stored digits-only. Optional everywhere — empty on every
  /// driver added before the driver-KYC migration, and still allowed to stay
  /// empty. The FORMAT is validated (here and on the server) only when a value
  /// is actually supplied.
  ///
  /// This is NOT the legacy `aadhaar_masked` column on the drivers table: that
  /// one was never read or written by any code and is superseded by this field,
  /// which holds the full value.
  final String aadhaar;

  /// 10-character PAN, upper-case. Same optional rule as [aadhaar].
  final String pan;

  // Uploaded Aadhaar / PAN card images — persisted in the backend `documents`
  // JSONB (one upload endpoint, only the ?type differs), never sent by [toJson].
  final String aadhaarFileKey;
  final String aadhaarFileName;
  final String panFileKey;
  final String panFileName;
  final int version;

  const Driver({
    required this.id,
    required this.name,
    required this.mobile,
    required this.licenseNo,
    this.licenseExpiry,
    this.address = '',
    this.aadhaar = '',
    this.pan = '',
    this.aadhaarFileKey = '',
    this.aadhaarFileName = '',
    this.panFileKey = '',
    this.panFileName = '',
    this.version = 0,
  });

  bool get hasAadhaarDocument => aadhaarFileKey.isNotEmpty;
  bool get hasPanDocument => panFileKey.isNotEmpty;

  factory Driver.fromJson(Map<String, dynamic> json) {
    String? expiry = json['license_expiry'] as String?;
    if (expiry != null && expiry.length > 10) expiry = expiry.substring(0, 10);
    // Guarded the same way as Transporter's bank_account: a null (or anything
    // that is not a map) yields an empty map rather than a cast error.
    final docs = (json['documents'] is Map)
        ? (json['documents'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return Driver(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      mobile: (json['mobile'] as String?) ?? '',
      licenseNo: (json['license_no'] as String?) ?? '',
      licenseExpiry: (expiry == null || expiry.isEmpty) ? null : expiry,
      address: (json['address'] as String?) ?? '',
      aadhaar: (json['aadhaar'] as String?) ?? '',
      pan: (json['pan'] as String?) ?? '',
      aadhaarFileKey: (docs['aadhaar_file_key'] as String?) ?? '',
      aadhaarFileName: (docs['aadhaar_file_name'] as String?) ?? '',
      panFileKey: (docs['pan_file_key'] as String?) ?? '',
      panFileName: (docs['pan_file_name'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (mobile.isNotEmpty) 'mobile': mobile,
    if (licenseNo.isNotEmpty) 'license_no': licenseNo,
    if (licenseExpiry != null && licenseExpiry!.isNotEmpty)
      'license_expiry': licenseExpiry,
    if (address.isNotEmpty) 'address': address,
    // Omitted when empty rather than sent as '': a legacy driver has no KYC
    // yet, and the server validates the FORMAT of whatever it receives, so ''
    // would turn an optional field into a validation error.
    if (aadhaar.isNotEmpty) 'aadhaar': aadhaar,
    if (pan.isNotEmpty) 'pan': pan,
  };

  Driver copyWith({
    String? name,
    String? mobile,
    String? licenseNo,
    String? licenseExpiry,
    String? address,
    String? aadhaar,
    String? pan,
    String? aadhaarFileKey,
    String? aadhaarFileName,
    String? panFileKey,
    String? panFileName,
    int? version,
  }) {
    return Driver(
      id: id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      licenseNo: licenseNo ?? this.licenseNo,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      address: address ?? this.address,
      aadhaar: aadhaar ?? this.aadhaar,
      pan: pan ?? this.pan,
      aadhaarFileKey: aadhaarFileKey ?? this.aadhaarFileKey,
      aadhaarFileName: aadhaarFileName ?? this.aadhaarFileName,
      panFileKey: panFileKey ?? this.panFileKey,
      panFileName: panFileName ?? this.panFileName,
      version: version ?? this.version,
    );
  }
}
