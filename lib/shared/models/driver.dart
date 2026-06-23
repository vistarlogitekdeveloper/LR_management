class Driver {
  final String id;
  final String name;
  final String mobile;
  final String licenseNo;
  final String? licenseExpiry; // YYYY-MM-DD
  final String address;
  final int version;

  const Driver({
    required this.id,
    required this.name,
    required this.mobile,
    required this.licenseNo,
    this.licenseExpiry,
    this.address = '',
    this.version = 0,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    String? expiry = json['license_expiry'] as String?;
    if (expiry != null && expiry.length > 10) expiry = expiry.substring(0, 10);
    return Driver(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      mobile: (json['mobile'] as String?) ?? '',
      licenseNo: (json['license_no'] as String?) ?? '',
      licenseExpiry: (expiry == null || expiry.isEmpty) ? null : expiry,
      address: (json['address'] as String?) ?? '',
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
      };

  Driver copyWith({
    String? name,
    String? mobile,
    String? licenseNo,
    String? licenseExpiry,
    String? address,
    int? version,
  }) {
    return Driver(
      id: id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      licenseNo: licenseNo ?? this.licenseNo,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      address: address ?? this.address,
      version: version ?? this.version,
    );
  }
}
