class Consignee {
  final String id;
  final String name;
  final String gst;
  final String location; // maps to backend `city`
  final String state;
  final String address;
  final String contact;
  final String mobile;
  final String email;
  final int version;

  const Consignee({
    required this.id,
    required this.name,
    required this.gst,
    required this.location,
    required this.address,
    required this.contact,
    required this.mobile,
    this.state = '',
    this.email = '',
    this.version = 0,
  });

  factory Consignee.fromJson(Map<String, dynamic> json) => Consignee(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        gst: (json['gstin'] as String?) ?? (json['gst'] as String?) ?? '',
        location: (json['city'] as String?) ??
            (json['location'] as String?) ??
            '',
        state: (json['state'] as String?) ?? '',
        address: (json['address'] as String?) ?? '',
        contact: (json['contact_person'] as String?) ??
            (json['contact'] as String?) ??
            '',
        mobile: (json['mobile'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'gstin': gst,
        'city': location,
        if (state.isNotEmpty) 'state': state,
        'address': address,
        'contact_person': contact,
        'mobile': mobile,
        if (email.isNotEmpty) 'email': email,
      };

  Consignee copyWith({
    String? name,
    String? gst,
    String? location,
    String? state,
    String? address,
    String? contact,
    String? mobile,
    String? email,
    int? version,
  }) {
    return Consignee(
      id: id,
      name: name ?? this.name,
      gst: gst ?? this.gst,
      location: location ?? this.location,
      state: state ?? this.state,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      version: version ?? this.version,
    );
  }
}
