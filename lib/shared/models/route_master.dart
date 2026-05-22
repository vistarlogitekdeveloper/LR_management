class RouteMaster {
  final String id;
  final String fromCity;
  final String toCity;
  final double distanceKm;
  final double baseRate;

  const RouteMaster({
    required this.id,
    required this.fromCity,
    required this.toCity,
    required this.distanceKm,
    required this.baseRate,
  });

  String get name => '$fromCity → $toCity';

  RouteMaster copyWith({
    String? fromCity,
    String? toCity,
    double? distanceKm,
    double? baseRate,
  }) {
    return RouteMaster(
      id: id,
      fromCity: fromCity ?? this.fromCity,
      toCity: toCity ?? this.toCity,
      distanceKm: distanceKm ?? this.distanceKm,
      baseRate: baseRate ?? this.baseRate,
    );
  }
}
