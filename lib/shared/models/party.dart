class Party {
  final String id;
  final String name;
  final String gst;
  final String city;
  final String address;
  final String contact;
  final String mobile;
  final String email;
  // Role flags — a party may be any combination of these. The LR pickers
  // filter by role (consignor / consignee / customer); at least one is set.
  final bool isConsignor;
  final bool isConsignee;
  final bool isCustomer;
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
    this.isConsignor = false,
    this.isConsignee = false,
    this.isCustomer = false,
    this.version = 0,
  });

  /// Human label for the set roles, e.g. "Consignor · Customer".
  String get roleLabel {
    final r = <String>[
      if (isConsignor) 'Consignor',
      if (isConsignee) 'Consignee',
      if (isCustomer) 'Customer',
    ];
    return r.isEmpty ? '—' : r.join(' · ');
  }

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
    // Tolerant of a backend that predates the role columns (defaults false).
    isConsignor: (json['is_consignor'] as bool?) ?? false,
    isConsignee: (json['is_consignee'] as bool?) ?? false,
    isCustomer: (json['is_customer'] as bool?) ?? false,
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
    'is_consignor': isConsignor,
    'is_consignee': isConsignee,
    'is_customer': isCustomer,
  };

  Party copyWith({
    String? name,
    String? gst,
    String? city,
    String? address,
    String? contact,
    String? mobile,
    String? email,
    bool? isConsignor,
    bool? isConsignee,
    bool? isCustomer,
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
      isConsignor: isConsignor ?? this.isConsignor,
      isConsignee: isConsignee ?? this.isConsignee,
      isCustomer: isCustomer ?? this.isCustomer,
      version: version ?? this.version,
    );
  }
}
