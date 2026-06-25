import '../../core/utils/json_parse.dart';

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
  final String? routeId; // assigned/default route
  final String routeName; // "From → To"
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
    this.routeId,
    this.routeName = '',
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
    final dr =
        nested('currentDriver') ?? nested('current_driver') ?? nested('driver');
    final rt = nested('route');
    String routeName = '';
    if (rt != null) {
      final from = (rt['from_city'] as String?) ?? '';
      final to = (rt['to_city'] as String?) ?? '';
      if (from.isNotEmpty || to.isNotEmpty) routeName = '$from → $to';
    }

    return Vehicle(
      id: json['id'] as String,
      number: (json['registration_no'] as String?) ??
          (json['number'] as String?) ??
          '',
      typeId: (json['vehicle_type_id'] as String?) ?? '',
      type: (vt?['label'] as String?) ?? (json['type'] as String?) ?? '',
      capacityMt: asDouble(json['capacity_mt']),
      transporterId: json['transporter_id'] as String?,
      transporterName: (tr?['name'] as String?) ?? '',
      currentDriverId: json['current_driver_id'] as String?,
      driver: (dr?['name'] as String?) ?? (json['driver'] as String?) ?? '',
      driverMobile:
          (dr?['mobile'] as String?) ?? (json['driverMobile'] as String?) ?? '',
      routeId: json['route_id'] as String?,
      routeName: routeName,
      version: asInt(json['version']),
    );
  }

  // Optional FKs are always sent (null when unset) so an edit can clear them.
  Map<String, dynamic> toJson() => {
        'registration_no': number,
        'vehicle_type_id': typeId.isNotEmpty ? typeId : null,
        'capacity_mt': capacityMt > 0 ? capacityMt : null,
        'transporter_id': (transporterId != null && transporterId!.isNotEmpty)
            ? transporterId
            : null,
        'current_driver_id':
            (currentDriverId != null && currentDriverId!.isNotEmpty)
                ? currentDriverId
                : null,
        'route_id': (routeId != null && routeId!.isNotEmpty) ? routeId : null,
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
    String? routeId,
    String? routeName,
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
      routeId: routeId ?? this.routeId,
      routeName: routeName ?? this.routeName,
      version: version ?? this.version,
    );
  }
}
