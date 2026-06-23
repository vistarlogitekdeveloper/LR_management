import '../../core/utils/json_parse.dart';

class RouteMaster {
  final String id;
  final String fromCity;
  final String toCity;
  final double distanceKm;
  final double baseRate;
  final int version;

  const RouteMaster({
    required this.id,
    required this.fromCity,
    required this.toCity,
    required this.distanceKm,
    required this.baseRate,
    this.version = 0,
  });

  String get name => '$fromCity → $toCity';

  factory RouteMaster.fromJson(Map<String, dynamic> json) => RouteMaster(
        id: json['id'] as String,
        fromCity: (json['from_city'] as String?) ?? '',
        toCity: (json['to_city'] as String?) ?? '',
        distanceKm: asDouble(json['distance_km']),
        baseRate: asDouble(json['base_rate']),
        version: asInt(json['version']),
      );

  Map<String, dynamic> toJson() => {
        'from_city': fromCity,
        'to_city': toCity,
        if (distanceKm > 0) 'distance_km': distanceKm,
        if (baseRate > 0) 'base_rate': baseRate,
      };

  RouteMaster copyWith({
    String? fromCity,
    String? toCity,
    double? distanceKm,
    double? baseRate,
    int? version,
  }) {
    return RouteMaster(
      id: id,
      fromCity: fromCity ?? this.fromCity,
      toCity: toCity ?? this.toCity,
      distanceKm: distanceKm ?? this.distanceKm,
      baseRate: baseRate ?? this.baseRate,
      version: version ?? this.version,
    );
  }
}
