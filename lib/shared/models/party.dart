class Party {
  final String id;
  final String name;
  final String gst;
  final String city;
  final String address;
  final String contact;
  final String mobile;
  final String email;
  final int version;

  const Party({
    required this.id,
    required this.name,
    required this.gst,
    required this.city,
    required this.address,
    required this.contact,
    required this.mobile,
    required this.email,
    this.version = 0,
  });

  factory Party.fromJson(Map<String, dynamic> json) => Party(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    gst: (json['gstin'] as String?) ?? (json['gst'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    address: (json['address'] as String?) ?? '',
    contact:
        (json['contact_person'] as String?) ??
        (json['contact'] as String?) ??
        '',
    mobile: (json['mobile'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    version: (json['version'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'gstin': gst,
    'city': city,
    'address': address,
    'contact_person': contact,
    'mobile': mobile,
    'email': email,
  };

  Party copyWith({
    String? name,
    String? gst,
    String? city,
    String? address,
    String? contact,
    String? mobile,
    String? email,
    int? version,
  }) {
    return Party(
      id: id,
      name: name ?? this.name,
      gst: gst ?? this.gst,
      city: city ?? this.city,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      version: version ?? this.version,
    );
  }
}
