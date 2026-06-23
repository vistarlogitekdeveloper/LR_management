class Vehicle {
  final String id;
  final String number; // registration_no
  final String typeId; // vehicle_type_id (lookup)
  final String type; // vehicle type label
  final double capacityMt;
  final String? transporterId;
  final String transporterName;
  final String? currentDriverId;
  final String driver; // current driver name
  final String driverMobile;
  final int version;

  const Vehicle({
    required this.id,
    required this.number,
    this.typeId = '',
    this.type = '',
    this.capacityMt = 0,
    this.transporterId,
    this.transporterName = '',
    this.currentDriverId,
    this.driver = '',
    this.driverMobile = '',
    this.version = 0,
  });

  /// Display helpers kept for backwards compatibility with existing screens.
  String get capacity => capacityMt > 0
      ? '${capacityMt.toStringAsFixed(capacityMt.truncateToDouble() == capacityMt ? 0 : 1)} MT'
      : '';
  String get mode => 'Road';
  String get pmark => '';

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      return v is Map ? v.cast<String, dynamic>() : null;
    }

    final vt = nested('vehicleType') ?? nested('vehicle_type');
    final tr = nested('transporter');
    final dr = nested('currentDriver') ?? nested('current_driver') ?? nested('driver');

    return Vehicle(
      id: json['id'] as String,
      number: (json['registration_no'] as String?) ??
          (json['number'] as String?) ??
          '',
      typeId: (json['vehicle_type_id'] as String?) ?? '',
      type: (vt?['label'] as String?) ?? (json['type'] as String?) ?? '',
      capacityMt: (json['capacity_mt'] as num?)?.toDouble() ?? 0,
      transporterId: json['transporter_id'] as String?,
      transporterName: (tr?['name'] as String?) ?? '',
      currentDriverId: json['current_driver_id'] as String?,
      driver: (dr?['name'] as String?) ?? (json['driver'] as String?) ?? '',
      driverMobile:
          (dr?['mobile'] as String?) ?? (json['driverMobile'] as String?) ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'registration_no': number,
        if (typeId.isNotEmpty) 'vehicle_type_id': typeId,
        if (capacityMt > 0) 'capacity_mt': capacityMt,
        if (transporterId != null && transporterId!.isNotEmpty)
          'transporter_id': transporterId,
        if (currentDriverId != null && currentDriverId!.isNotEmpty)
          'current_driver_id': currentDriverId,
      };

  Vehicle copyWith({
    String? number,
    String? typeId,
    String? type,
    double? capacityMt,
    String? transporterId,
    String? transporterName,
    String? currentDriverId,
    String? driver,
    String? driverMobile,
    int? version,
  }) {
    return Vehicle(
      id: id,
      number: number ?? this.number,
      typeId: typeId ?? this.typeId,
      type: type ?? this.type,
      capacityMt: capacityMt ?? this.capacityMt,
      transporterId: transporterId ?? this.transporterId,
      transporterName: transporterName ?? this.transporterName,
      currentDriverId: currentDriverId ?? this.currentDriverId,
      driver: driver ?? this.driver,
      driverMobile: driverMobile ?? this.driverMobile,
      version: version ?? this.version,
    );
  }
}
