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

/// How fresh a running trip's signal is (server: trackingController.signalOf).
enum FleetSignal {
  /// A location fix within the last 24 h.
  live,

  /// No fix yet, but the trip is less than a day old.
  awaiting,

  /// Nothing for over a day — almost always a finished trip whose LR was never
  /// marked Delivered, so it (and the driver's SIM) was never released.
  noSignal,
}

/// The same 24 h as the server's LIVE_SIGNAL_HOURS.
const fleetLiveWindow = Duration(hours: 24);

/// The server's rule, for a response from a backend too old to send `signal`.
FleetSignal fleetSignalOf({
  DateTime? lastFixAt,
  DateTime? trackingSince,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  if (lastFixAt != null) {
    return t.difference(lastFixAt) <= fleetLiveWindow
        ? FleetSignal.live
        : FleetSignal.noSignal;
  }
  // An old server sends no start time either: give the trip the benefit of the
  // doubt rather than hiding it.
  if (trackingSince == null || t.difference(trackingSince) <= fleetLiveWindow) {
    return FleetSignal.awaiting;
  }
  return FleetSignal.noSignal;
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

  /// When tracking began (the LR's creation, when it auto-starts).
  final DateTime? trackingSince;

  /// Region short code ("PUN", "SBN") — from the server, else from the LR
  /// number's middle segment (LR/PUN/26-27/01278).
  final String regionCode;
  final String? regionName;
  final FleetSignal signal;

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
    this.trackingSince,
    this.regionCode = '',
    this.regionName,
    this.signal = FleetSignal.live,
  });

  factory FleetVehicle.fromJson(Map<String, dynamic> j) {
    final location = (j['location'] is Map)
        ? TrackPoint.fromJson((j['location'] as Map).cast<String, dynamic>())
        : null;
    final since = _dt(j['tracking_since']);
    final number = (j['lr_number'] ?? '').toString();
    final segments = number.split('/');
    final serverCode = (j['region_code'] ?? '').toString().trim();
    return FleetVehicle(
      lrId: j['lr_id'].toString(),
      lrNumber: number,
      fromCity: j['from_city'] as String?,
      toCity: j['to_city'] as String?,
      truckNumber: j['truck_number'] as String?,
      driverName: j['driver_name'] as String?,
      consentStatus: j['consent_status'] as String?,
      trackingState: j['tracking_state'] as String?,
      location: location,
      trackingSince: since,
      regionCode:
          (serverCode.isNotEmpty
                  ? serverCode
                  : (segments.length >= 3 ? segments[1] : ''))
              .toUpperCase(),
      regionName: j['region_name'] as String?,
      signal: switch (j['signal']) {
        'live' => FleetSignal.live,
        'awaiting' => FleetSignal.awaiting,
        'no_signal' => FleetSignal.noSignal,
        _ => fleetSignalOf(
          lastFixAt: _dt(j['last_fix_at']) ?? location?.at,
          trackingSince: since,
        ),
      },
    );
  }

  /// The trip itself is over (an older server still lists these).
  bool get tripOver {
    final s = (trackingState ?? '').toUpperCase();
    return s == 'STOPPED' || s == 'ENDED';
  }
}

/// Full tracking detail for one LR (trail + consent).
class LrTracking {
  final String lrId;
  final String? lrNumber;
  final String? fromCity;
  final String? toCity;
  final String? truckNumber;
  final String? driverName;

  /// The driver's mobile, and whether tracking can use it. Let the screen say
  /// what is wrong BEFORE Start is pressed — the press used to be the first
  /// place a bad number surfaced. All null from a server too old to send them,
  /// in which case nothing is assumed.
  final String? driverMobile;
  final bool? driverMobileValid;
  final bool? driverActive;

  /// Delivered or cancelled: tracking can no longer be started.
  final bool lrClosed;

  /// The trip was stopped (taken over, driver changed) or ended by the
  /// provider, and the LR is open: tracking may be started again.
  final bool canRestart;
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
    this.driverMobile,
    this.driverMobileValid,
    this.driverActive,
    this.lrClosed = false,
    this.canRestart = false,
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
            (j['current_location'] as Map).cast<String, dynamic>(),
          )
        : null;
    return LrTracking(
      lrId: j['lr_id'].toString(),
      lrNumber: j['lr_number'] as String?,
      fromCity: j['from_city'] as String?,
      toCity: j['to_city'] as String?,
      truckNumber: j['truck_number'] as String?,
      driverName: j['driver_name'] as String?,
      driverMobile: j['driver_mobile'] as String?,
      driverMobileValid: j['driver_mobile_valid'] as bool?,
      driverActive: j['driver_active'] as bool?,
      lrClosed: j['lr_closed'] == true,
      canRestart: j['can_restart'] == true,
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
                (j['remaining_route'] as Map).cast<String, dynamic>(),
              );
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
    return LrTracking.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  /// Re-check the driver-SIM consent for an LR (refreshes the stored status).
  Future<ConsentResult> recheckConsent(String lrId) async {
    final res = await _api.dio.post('/tracking/lr/$lrId/consent-recheck');
    return ConsentResult.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  /// Start SIM tracking for an LR whose driver was assigned after creation
  /// (idempotent server-side: a no-op if a trip already exists).
  ///
  /// Pass [takeover] only after the operator has agreed to it: the driver's
  /// phone can carry one trip at a time, so taking it over ENDS the trip that
  /// currently owns it and stops tracking for that LR. A plain call refuses with
  /// 409 `SIM_BUSY` instead, and the response carries `can_takeover` plus
  /// `blocking_lrs` so the UI can name what would stop.
  Future<void> startTracking(String lrId, {bool takeover = false}) async {
    await _api.dio.post(
      '/tracking/lr/$lrId/start',
      data: takeover ? {'takeover': true} : null,
    );
  }

  /// Generate (or fetch the cached) public shareable tracking link so a
  /// customer/consignee can watch the truck live without an app login.
  Future<String> publicLink(String lrId) async {
    final res = await _api.dio.post('/tracking/lr/$lrId/public-link');
    return ((res.data['data'] as Map)['link'] ?? '').toString();
  }
}
