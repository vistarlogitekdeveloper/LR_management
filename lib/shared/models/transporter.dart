class Transporter {
  final String id;
  final String name;
  final String pan;
  final String tds;

  const Transporter({
    required this.id,
    required this.name,
    required this.pan,
    required this.tds,
  });

  Transporter copyWith({String? name, String? pan, String? tds}) {
    return Transporter(
      id: id,
      name: name ?? this.name,
      pan: pan ?? this.pan,
      tds: tds ?? this.tds,
    );
  }
}
