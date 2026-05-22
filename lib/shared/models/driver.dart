class Driver {
  final String id;
  final String name;
  final String mobile;
  final String licenseNo;
  final String? licenseExpiry;
  final String address;

  const Driver({
    required this.id,
    required this.name,
    required this.mobile,
    required this.licenseNo,
    this.licenseExpiry,
    this.address = '',
  });

  Driver copyWith({
    String? name,
    String? mobile,
    String? licenseNo,
    String? licenseExpiry,
    String? address,
  }) {
    return Driver(
      id: id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      licenseNo: licenseNo ?? this.licenseNo,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      address: address ?? this.address,
    );
  }
}
