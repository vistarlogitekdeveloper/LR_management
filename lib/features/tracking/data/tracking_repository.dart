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

/// Why a halt was acknowledged — the server's tripHalt.ACK_REASONS.
enum HaltReason { driverRest, breakdown, accident, documents, checkpost, other }

extension HaltReasonX on HaltReason {
  String get code => switch (this) {
    HaltReason.driverRest => 'DRIVER_REST',
    HaltReason.breakdown => 'BREAKDOWN',
    HaltReason.accident => 'ACCIDENT',
    HaltReason.documents => 'DOCUMENTS',
    HaltReason.checkpost => 'CHECKPOST',
    HaltReason.other => 'OTHER',
  };

  String get label => switch (this) {
    HaltReason.driverRest => 'Driver rest',
    HaltReason.breakdown => 'Breakdown',
    HaltReason.accident => 'Accident',
    HaltReason.documents => 'Waiting for documents',
    HaltReason.checkpost => 'RTO / police check',
    HaltReason.other => 'Other',
  };

  static HaltReason? fromCode(String? s) {
    for (final r in HaltReason.values) {
      if (r.code == s) return r;
    }
    return null;
  }
}

/// The hours at which a halt is alerted (server: LRM_HALT_ALERT_HOURS).
const haltAlertHours = 10;

/// A stretch where the truck's fixes stayed within ~2 km of one spot (server:
/// services/tripHalt.service.js). Recorded from 2 h; alerted at 10 h.
class TripHalt {
  final String id;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final bool ongoing;
  final double hours;
  final double? lat;
  final double? lng;
  final String? city;
  final String? address;
  final bool alerted;
  final DateTime? acknowledgedAt;
  final HaltReason? ackReason;
  final String? ackNote;

  const TripHalt({
    required this.id,
    this.startedAt,
    this.endedAt,
    this.ongoing = false,
    this.hours = 0,
    this.lat,
    this.lng,
    this.city,
    this.address,
    this.alerted = false,
    this.acknowledgedAt,
    this.ackReason,
    this.ackNote,
  });

  factory TripHalt.fromJson(Map<String, dynamic> j) => TripHalt(
    id: j['id'].toString(),
    startedAt: _dt(j['started_at']),
    endedAt: _dt(j['ended_at']),
    ongoing: j['ongoing'] == true,
    hours: (j['hours'] is num) ? (j['hours'] as num).toDouble() : 0,
    lat: j['lat'] == null ? null : _d(j['lat']),
    lng: j['lng'] == null ? null : _d(j['lng']),
    city: j['city'] as String?,
    address: j['address'] as String?,
    alerted: j['alerted'] == true,
    acknowledgedAt: _dt(j['acknowledged_at']),
    ackReason: HaltReasonX.fromCode(j['ack_reason'] as String?),
    ackNote: j['ack_note'] as String?,
  );

  /// Long enough to have been alerted — what the Live Tracking chip counts.
  bool get overAlertLimit => hours >= haltAlertHours;
  bool get acknowledged => acknowledgedAt != null;

  /// "10 h 20 m"
  String get durationLabel {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return m == 0 ? '$h h' : '$h h $m m';
  }
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
  final String? driverMobile;

  /// The halt the truck is in right now (2 h+), or null.
  final TripHalt? halt;

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
    this.driverMobile,
    this.halt,
  });

  /// Halted long enough to have raised the alert (10 h+).
  bool get haltAlert => halt != null && halt!.ongoing && halt!.overAlertLimit;

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
      driverMobile: j['driver_mobile'] as String?,
      halt: (j['halt'] is Map)
          ? TripHalt.fromJson((j['halt'] as Map).cast<String, dynamic>())
          : null,
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

  /// Every recorded halt of this trip (2 h+), oldest first. Empty from a
  /// server that does not track halts yet.
  final List<TripHalt> halts;

  /// The server tracks halts (sends `halts`, even empty). False from an older
  /// backend, so the screen does not claim "no halts" it never checked for.
  final bool haltsSupported;
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
    this.halts = const [],
    this.haltsSupported = false,
  });

  /// The halt the truck is in right now, if any.
  TripHalt? get currentHalt {
    for (final h in halts.reversed) {
      if (h.ongoing) return h;
    }
    return null;
  }

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
      halts: (j['halts'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => TripHalt.fromJson(m.cast<String, dynamic>()))
          .toList(),
      haltsSupported: j['halts'] is List,
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
  /// Acknowledge a halt alert with the reason — stops the 24 h reminder.
  Future<TripHalt> acknowledgeHalt(
    String lrId,
    String haltId, {
    required HaltReason reason,
    String? note,
  }) async {
    final res = await _api.dio.post(
      '/tracking/lr/$lrId/halts/$haltId/ack',
      data: {
        'reason': reason.code,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return TripHalt.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<String> publicLink(String lrId) async {
    final res = await _api.dio.post('/tracking/lr/$lrId/public-link');
    return ((res.data['data'] as Map)['link'] ?? '').toString();
  }
}
