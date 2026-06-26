import '../../core/utils/json_parse.dart';

class RouteMaster {
  final String id;
  final String fromCity;
  final String toCity;
  final double distanceKm;
  final double baseRate;
  final double customerRate;
  // Map-picked endpoints (Google Places). place_id is the stable key; lat/lng
  // + formatted address power the map and (later) geofencing.
  final String fromPlaceId;
  final double? fromLat;
  final double? fromLng;
  final String fromAddress;
  final String toPlaceId;
  final double? toLat;
  final double? toLng;
  final String toAddress;
  final int version;

  const RouteMaster({
    required this.id,
    required this.fromCity,
    required this.toCity,
    required this.distanceKm,
    required this.baseRate,
    this.customerRate = 0,
    this.fromPlaceId = '',
    this.fromLat,
    this.fromLng,
    this.fromAddress = '',
    this.toPlaceId = '',
    this.toLat,
    this.toLng,
    this.toAddress = '',
    this.version = 0,
  });

  String get name => '$fromCity → $toCity';
  bool get hasFromCoords => fromLat != null && fromLng != null;
  bool get hasToCoords => toLat != null && toLng != null;

  factory RouteMaster.fromJson(Map<String, dynamic> json) => RouteMaster(
    id: json['id'] as String,
    fromCity: (json['from_city'] as String?) ?? '',
    toCity: (json['to_city'] as String?) ?? '',
    distanceKm: asDouble(json['distance_km']),
    baseRate: asDouble(json['base_rate']),
    customerRate: asDouble(json['customer_rate']),
    fromPlaceId: (json['from_place_id'] as String?) ?? '',
    fromLat: asDoubleOrNull(json['from_lat']),
    fromLng: asDoubleOrNull(json['from_lng']),
    fromAddress: (json['from_address'] as String?) ?? '',
    toPlaceId: (json['to_place_id'] as String?) ?? '',
    toLat: asDoubleOrNull(json['to_lat']),
    toLng: asDoubleOrNull(json['to_lng']),
    toAddress: (json['to_address'] as String?) ?? '',
    version: asInt(json['version']),
  );

  Map<String, dynamic> toJson() => {
    'from_city': fromCity,
    'to_city': toCity,
    if (distanceKm > 0) 'distance_km': distanceKm,
    if (baseRate > 0) 'base_rate': baseRate,
    'customer_rate': customerRate > 0 ? customerRate : null,
    // Always sent (even null) so clearing a pin sticks on PATCH.
    'from_place_id': fromPlaceId.isEmpty ? null : fromPlaceId,
    'from_lat': fromLat,
    'from_lng': fromLng,
    'from_address': fromAddress.isEmpty ? null : fromAddress,
    'to_place_id': toPlaceId.isEmpty ? null : toPlaceId,
    'to_lat': toLat,
    'to_lng': toLng,
    'to_address': toAddress.isEmpty ? null : toAddress,
  };

  RouteMaster copyWith({
    String? fromCity,
    String? toCity,
    double? distanceKm,
    double? baseRate,
    double? customerRate,
    String? fromPlaceId,
    double? fromLat,
    double? fromLng,
    String? fromAddress,
    String? toPlaceId,
    double? toLat,
    double? toLng,
    String? toAddress,
    int? version,
  }) {
    return RouteMaster(
      id: id,
      fromCity: fromCity ?? this.fromCity,
      toCity: toCity ?? this.toCity,
      distanceKm: distanceKm ?? this.distanceKm,
      baseRate: baseRate ?? this.baseRate,
      customerRate: customerRate ?? this.customerRate,
      fromPlaceId: fromPlaceId ?? this.fromPlaceId,
      fromLat: fromLat ?? this.fromLat,
      fromLng: fromLng ?? this.fromLng,
      fromAddress: fromAddress ?? this.fromAddress,
      toPlaceId: toPlaceId ?? this.toPlaceId,
      toLat: toLat ?? this.toLat,
      toLng: toLng ?? this.toLng,
      toAddress: toAddress ?? this.toAddress,
      version: version ?? this.version,
    );
  }
}

/// A location chosen from the map picker.
class PickedLocation {
  final String placeId;
  final double lat;
  final double lng;
  final String address;
  const PickedLocation({
    required this.placeId,
    required this.lat,
    required this.lng,
    required this.address,
  });
}
