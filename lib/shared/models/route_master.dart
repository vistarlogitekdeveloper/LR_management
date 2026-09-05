import '../../core/utils/json_parse.dart';

class RouteMaster {
  final String id;
  final String fromCity;
  final String toCity;
  final double distanceKm;
  final double baseRate;
  final double customerRate;
  // Vehicle type (VEHICLE_TYPE lookup) — nullable; a route may have none.
  final String? vehicleTypeId;
  final String? vehicleTypeCode;
  final String? vehicleTypeLabel;
  // Vehicle capacity (VEHICLE_CAPACITY lookup) — nullable; copied onto LRs
  // created for this route.
  final String? capacityId;
  final String? capacityCode;
  final String? capacityLabel;
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
    this.vehicleTypeId,
    this.vehicleTypeCode,
    this.vehicleTypeLabel,
    this.capacityId,
    this.capacityCode,
    this.capacityLabel,
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

  /// A stored pair is only usable if it is actually a degree pair. Rows written
  /// by an earlier picker hold projected metres (lat ~25,555,074), and (0, 0) is
  /// what an uninitialised map widget saves. Treating either as a real pin makes
  /// the route un-editable — the form would re-send it and the server's
  /// coordinate guard rejects it — so both count as "no pin" and the user is
  /// asked to place one.
  static bool isUsableCoord(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      !(lat == 0 && lng == 0);

  bool get hasFromCoords => isUsableCoord(fromLat, fromLng);
  bool get hasToCoords => isUsableCoord(toLat, toLng);

  factory RouteMaster.fromJson(Map<String, dynamic> json) => RouteMaster(
    id: json['id'] as String,
    fromCity: (json['from_city'] as String?) ?? '',
    toCity: (json['to_city'] as String?) ?? '',
    distanceKm: asDouble(json['distance_km']),
    baseRate: asDouble(json['base_rate']),
    customerRate: asDouble(json['customer_rate']),
    vehicleTypeId:
        (json['vehicle_type_id'] as String?) ??
        ((json['vehicleType'] as Map?)?['id'] as String?),
    vehicleTypeCode: (json['vehicleType'] as Map?)?['code'] as String?,
    vehicleTypeLabel: (json['vehicleType'] as Map?)?['label'] as String?,
    capacityId:
        (json['capacity_id'] as String?) ??
        ((json['capacity'] as Map?)?['id'] as String?),
    capacityCode: (json['capacity'] as Map?)?['code'] as String?,
    capacityLabel: (json['capacity'] as Map?)?['label'] as String?,
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
    // Always sent (even null) so clearing the vehicle type sticks on PATCH.
    'vehicle_type_id': vehicleTypeId,
    // Always sent (even null) so clearing the capacity sticks on PATCH.
    'capacity_id': capacityId,
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
    String? vehicleTypeId,
    String? vehicleTypeCode,
    String? vehicleTypeLabel,
    String? capacityId,
    String? capacityCode,
    String? capacityLabel,
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
      vehicleTypeId: vehicleTypeId ?? this.vehicleTypeId,
      vehicleTypeCode: vehicleTypeCode ?? this.vehicleTypeCode,
      vehicleTypeLabel: vehicleTypeLabel ?? this.vehicleTypeLabel,
      capacityId: capacityId ?? this.capacityId,
      capacityCode: capacityCode ?? this.capacityCode,
      capacityLabel: capacityLabel ?? this.capacityLabel,
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

/// Where a picked location's coordinates came from. Recorded so the picker can
/// explain provenance and so a reviewer can tell a precise place pin from a
/// dragged map centre.
enum PickedLocationSource { search, pin, googleLink, stored }

/// A location chosen from the map picker.
class PickedLocation {
  final String placeId;
  final double lat;
  final double lng;

  /// Full formatted address, as returned by the geocoder.
  final String address;

  /// Short, user-editable label — a Nominatim display_name is far too long to
  /// use as a route's From/To city.
  final String name;
  final PickedLocationSource source;

  const PickedLocation({
    required this.placeId,
    required this.lat,
    required this.lng,
    required this.address,
    this.name = '',
    this.source = PickedLocationSource.stored,
  });

  /// The short label to show and to prefill the route's From/To label with:
  /// [name] when set, otherwise the address up to the first comma. Defined once
  /// here so the picker and the route form cannot drift apart.
  String get displayName {
    final n = name.trim();
    return n.isNotEmpty ? n : shortLabel(address);
  }

  /// The leading component of a formatted address — a Nominatim display_name
  /// runs to a dozen comma-separated parts and is unusable as a route label.
  /// Exposed so the picker can derive the same label before a [PickedLocation]
  /// exists.
  static String shortLabel(String address) {
    final a = address.trim();
    return a.contains(',') ? a.split(',').first.trim() : a;
  }

  PickedLocation copyWith({
    String? placeId,
    double? lat,
    double? lng,
    String? address,
    String? name,
    PickedLocationSource? source,
  }) {
    return PickedLocation(
      placeId: placeId ?? this.placeId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      address: address ?? this.address,
      name: name ?? this.name,
      source: source ?? this.source,
    );
  }
}
