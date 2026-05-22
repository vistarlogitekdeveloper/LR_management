class Consignee {
  final String id;
  final String name;
  final String gst;
  final String location;
  final String address;
  final String contact;
  final String mobile;

  const Consignee({
    required this.id,
    required this.name,
    required this.gst,
    required this.location,
    required this.address,
    required this.contact,
    required this.mobile,
  });

  Consignee copyWith({
    String? name,
    String? gst,
    String? location,
    String? address,
    String? contact,
    String? mobile,
  }) {
    return Consignee(
      id: id,
      name: name ?? this.name,
      gst: gst ?? this.gst,
      location: location ?? this.location,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      mobile: mobile ?? this.mobile,
    );
  }
}
