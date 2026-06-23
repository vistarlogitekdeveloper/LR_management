class Transporter {
  final String id;
  final String name;
  final String pan;
  final String tds; // 'Yes' / 'No' (maps to backend tds_applicable)
  final int version;

  const Transporter({
    required this.id,
    required this.name,
    required this.pan,
    required this.tds,
    this.version = 0,
  });

  bool get tdsApplicable => tds.toLowerCase() == 'yes';

  factory Transporter.fromJson(Map<String, dynamic> json) => Transporter(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        pan: (json['pan'] as String?) ?? '',
        tds: (json['tds_applicable'] as bool?) == true ? 'Yes' : 'No',
        version: (json['version'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (pan.isNotEmpty) 'pan': pan,
        'tds_applicable': tdsApplicable,
      };

  Transporter copyWith({String? name, String? pan, String? tds, int? version}) {
    return Transporter(
      id: id,
      name: name ?? this.name,
      pan: pan ?? this.pan,
      tds: tds ?? this.tds,
      version: version ?? this.version,
    );
  }
}
