class Consignor {
  final String id;
  final String name;
  final String gst;
  final String city;
  final String address;
  final String contact;
  final String mobile;
  final String email;

  const Consignor({
    required this.id,
    required this.name,
    required this.gst,
    required this.city,
    required this.address,
    required this.contact,
    required this.mobile,
    required this.email,
  });

  Consignor copyWith({
    String? name,
    String? gst,
    String? city,
    String? address,
    String? contact,
    String? mobile,
    String? email,
  }) {
    return Consignor(
      id: id,
      name: name ?? this.name,
      gst: gst ?? this.gst,
      city: city ?? this.city,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
    );
  }
}
