import '../../../core/network/api_client.dart';
import 'route_planner.dart';

/// Parse a lat/lng that may arrive as a number (from /tracking/active, where the
/// backend casts it) or a string (raw DECIMAL rows from /lr/:id/route).
double _d(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

DateTime? _dt(dynamic v) =>
    (v == null) ? null : DateTime.tryParse(v.toString())?.toLocal();

/// A single location fix (SIM or GPS).
class TrackPoint {
  final double lat;
  final double lng;
  final DateTime? at;
  final String? city;
  final String? address;
  final String? source; // 'sim' | 'gps'
  const TrackPoint({
    required this.lat,
    required this.lng,
    this.at,
    this.city,
    this.address,
    this.source,
  });

  factory TrackPoint.fromJson(Map<String, dynamic> j) => TrackPoint(
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        at: _dt(j['recorded_at']),
        city: j['city'] as String?,
        address: j['address'] as String?,
        source: j['source'] as String?,
      );
}

/// One actively-tracked vehicle/LR for the fleet view.
class FleetVehicle {
  final String lrId;
  final String lrNumber;
  final String? fromCity;
  final String? toCity;
  final String? truckNumber;
  final String? driverName;
  final String? consentStatus;
  final String? trackingState;
  final TrackPoint? location;
  const FleetVehicle({
    required this.lrId,
    required this.lrNumber,
    this.fromCity,
    this.toCity,
    this.truckNumber,
    this.driverName,
    this.consentStatus,
    this.trackingState,
    this.location,
  });

  factory FleetVehicle.fromJson(Map<String, dynamic> j) => FleetVehicle(
        lrId: j['lr_id'].toString(),
        lrNumber: (j['lr_number'] ?? '').toString(),
        fromCity: j['from_city'] as String?,
        toCity: j['to_city'] as String?,
        truckNumber: j['truck_number'] as String?,
        driverName: j['driver_name'] as String?,
        consentStatus: j['consent_status'] as String?,
        trackingState: j['tracking_state'] as String?,
        location: (j['location'] is Map)
            ? TrackPoint.fromJson((j['location'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// Full tracking detail for one LR (trail + consent).
class LrTracking {
  final String lrId;
  final String? lrNumber;
  final String? fromCity;
  final String? toCity;
  final String? truckNumber;
  final String? driverName;
  final String? consentStatus;
  final String? consentSuggestion;
  final String? trackingState;
  // Planned route (origin/destination + optional encoded polyline).
  final double? fromLat;
  final double? fromLng;
  final double? toLat;
  final double? toLng;
  final String? routePolyline;
  final List<RouteOption> routeOptions;
  final RouteOption? remainingRoute;
  final List<TrackPoint> history;
  final TrackPoint? current;
  // Public shareable tracking link, if one has already been generated (null
  // until the user first taps Share).
  final String? publicLink;
  const LrTracking({
    required this.lrId,
    this.lrNumber,
    this.fromCity,
    this.toCity,
    this.truckNumber,
    this.driverName,
    this.consentStatus,
    this.consentSuggestion,
    this.trackingState,
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.routePolyline,
    this.routeOptions = const [],
    this.remainingRoute,
    this.history = const [],
    this.current,
    this.publicLink,
  });

  factory LrTracking.fromJson(Map<String, dynamic> j) {
    final hist = (j['history'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TrackPoint.fromJson)
        .toList();
    final cur = (j['current_location'] is Map)
        ? TrackPoint.fromJson(
            (j['current_location'] as Map).cast<String, dynamic>())
        : null;
    return LrTracking(
      lrId: j['lr_id'].toString(),
      lrNumber: j['lr_number'] as String?,
      fromCity: j['from_city'] as String?,
      toCity: j['to_city'] as String?,
      truckNumber: j['truck_number'] as String?,
      driverName: j['driver_name'] as String?,
      consentStatus: j['consent_status'] as String?,
      consentSuggestion: j['consent_suggestion'] as String?,
      trackingState: j['tracking_state'] as String?,
      fromLat: j['from_lat'] != null ? _d(j['from_lat']) : null,
      fromLng: j['from_lng'] != null ? _d(j['from_lng']) : null,
      toLat: j['to_lat'] != null ? _d(j['to_lat']) : null,
      toLng: j['to_lng'] != null ? _d(j['to_lng']) : null,
      routePolyline: j['route_polyline'] as String?,
      routeOptions: (j['route_options'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => RouteOption.fromJson(m.cast<String, dynamic>()))
          .where((o) => o.points.length > 1)
          .toList(),
      remainingRoute: (j['remaining_route'] is Map)
          ? (() {
              final r = RouteOption.fromJson(
                  (j['remaining_route'] as Map).cast<String, dynamic>());
              return r.points.length > 1 ? r : null;
            })()
          : null,
      history: hist,
      current: cur,
      publicLink: j['public_link'] as String?,
    );
  }
}

class ConsentResult {
  final String? status;
  final String? suggestion;
  final String? operator;
  const ConsentResult({this.status, this.suggestion, this.operator});
  factory ConsentResult.fromJson(Map<String, dynamic> j) => ConsentResult(
        status: j['consent_status'] as String?,
        suggestion: j['consent_suggestion'] as String?,
        operator: j['operator'] as String?,
      );
}

class TrackingRepository {
  TrackingRepository(this._api);
  final ApiClient _api;

  /// All actively-tracked vehicles (one row per LR) with their latest fix.
  Future<List<FleetVehicle>> activeVehicles() async {
    final res = await _api.dio.get('/tracking/active');
    final rows = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return rows.map(FleetVehicle.fromJson).toList();
  }

  /// Trail + consent for one LR.
  Future<LrTracking> lrTracking(String lrId) async {
    final res = await _api.dio.get('/tracking/lr/$lrId/route');
    return LrTracking.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  /// Re-check the driver-SIM consent for an LR (refreshes the stored status).
  Future<ConsentResult> recheckConsent(String lrId) async {
    final res = await _api.dio.post('/tracking/lr/$lrId/consent-recheck');
    return ConsentResult.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  /// Start SIM tracking for an LR whose driver was assigned after creation
  /// (idempotent server-side: a no-op if a trip already exists).
  Future<void> startTracking(String lrId) async {
    await _api.dio.post('/tracking/lr/$lrId/start');
  }

  /// Generate (or fetch the cached) public shareable tracking link so a
  /// customer/consignee can watch the truck live without an app login.
  Future<String> publicLink(String lrId) async {
    final res = await _api.dio.post('/tracking/lr/$lrId/public-link');
    return ((res.data['data'] as Map)['link'] ?? '').toString();
  }
}
