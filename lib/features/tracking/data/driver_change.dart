/// A driver handover on a trip, and what changing the driver did — the
/// server's services/driverChange.service.js.
library;

DateTime? _dt(dynamic v) =>
    (v == null) ? null : DateTime.tryParse(v.toString())?.toLocal();

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// One handover: who handed over to whom, when, and where the truck was.
class DriverChange {
  final String id;
  final DateTime? changedAt;
  final String? fromName;
  final String? fromMobile;
  final String? toName;
  final String? toMobile;
  final String? note;
  final double? lat;
  final double? lng;
  final String? city;

  /// `TRACKING` (Change driver on Track LR) or `LR_EDIT` (the LR form).
  final String? source;

  const DriverChange({
    required this.id,
    this.changedAt,
    this.fromName,
    this.fromMobile,
    this.toName,
    this.toMobile,
    this.note,
    this.lat,
    this.lng,
    this.city,
    this.source,
  });

  factory DriverChange.fromJson(Map<String, dynamic> j) => DriverChange(
    id: j['id'].toString(),
    changedAt: _dt(j['changed_at']),
    fromName: j['from_driver_name'] as String?,
    fromMobile: j['from_mobile'] as String?,
    toName: j['to_driver_name'] as String?,
    toMobile: j['to_mobile'] as String?,
    note: j['note'] as String?,
    lat: _d(j['lat']),
    lng: _d(j['lng']),
    city: j['city'] as String?,
    source: j['source'] as String?,
  );

  bool get fromLrEdit => source == 'LR_EDIT';
}

/// How far moving tracking to the new driver's phone got.
enum TrackingMove {
  /// A trip runs on the new phone; the new driver may still have to consent.
  started,

  /// The provider refused — [DriverChangeResult.code] says why (`SIM_BUSY`:
  /// the new phone is on another truck's trip; a takeover is offered).
  refused,

  /// The provider could not be reached; Start tracking can be pressed again.
  failed,

  /// Both driver records share one phone: the running trip was already right.
  samePhone,

  /// SIM tracking is switched off on the server.
  disabled,
}

TrackingMove _move(String? s) => switch (s) {
  'STARTED' => TrackingMove.started,
  'START_REFUSED' => TrackingMove.refused,
  'SAME_PHONE' => TrackingMove.samePhone,
  'DISABLED' => TrackingMove.disabled,
  _ => TrackingMove.failed,
};

/// The answer of POST /tracking/lr/:id/change-driver. The driver change has
/// been made whatever [move] says.
class DriverChangeResult {
  final String? driverName;
  final String? driverMobile;

  /// Other open LRs on the same truck and trip, switched with this one.
  final List<String> alsoChanged;

  /// The halt the truck stood in during the handover was closed.
  final bool closedHalt;

  /// The shared live link followed the old trip; Share makes a new one.
  final bool publicLinkReset;

  final TrackingMove move;
  final String? code;
  final String? message;
  final String? consentStatus;
  final String? consentSuggestion;

  /// The provider did not confirm the old phone's trip ended. Tracking no
  /// longer reads it either way; it ends on its own at the provider.
  final bool oldTripEndFailed;

  const DriverChangeResult({
    this.driverName,
    this.driverMobile,
    this.alsoChanged = const [],
    this.closedHalt = false,
    this.publicLinkReset = false,
    this.move = TrackingMove.failed,
    this.code,
    this.message,
    this.consentStatus,
    this.consentSuggestion,
    this.oldTripEndFailed = false,
  });

  factory DriverChangeResult.fromJson(Map<String, dynamic> j) {
    final driver = (j['driver'] is Map)
        ? (j['driver'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final t = (j['tracking'] is Map)
        ? (j['tracking'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return DriverChangeResult(
      driverName: driver['name'] as String?,
      driverMobile: driver['mobile'] as String?,
      alsoChanged: (j['also_changed'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      closedHalt: j['closed_halt'] == true,
      publicLinkReset: j['public_link_reset'] == true,
      move: _move(t['state'] as String?),
      code: t['code'] as String?,
      message: t['message'] as String?,
      consentStatus: t['consent_status'] as String?,
      consentSuggestion: t['consent_suggestion'] as String?,
      oldTripEndFailed: t['old_trip_end_failed'] == true,
    );
  }

  /// The new phone is on another truck's trip: Start tracking will offer to
  /// take it over (the screen's existing SIM-busy dialog).
  bool get simBusy => move == TrackingMove.refused && code == 'SIM_BUSY';

  /// What to tell the operator, in one or two sentences.
  String get summary {
    final who = driverName ?? 'the new driver';
    final mates = alsoChanged.isEmpty
        ? ''
        : ' ${alsoChanged.join(', ')} on the same truck changed too.';
    final tracking = switch (move) {
      TrackingMove.started =>
        (consentStatus ?? '').toUpperCase() == 'ALLOWED'
            ? "Tracking now follows $who's phone."
            : "Tracking moved to $who's phone — $who must approve the SIM "
                  'consent before locations arrive.',
      TrackingMove.samePhone =>
        "$who uses the same phone, so tracking carries on unchanged.",
      TrackingMove.disabled => 'SIM tracking is switched off.',
      TrackingMove.refused =>
        message ?? "Tracking could not start on $who's phone.",
      TrackingMove.failed =>
        message ??
            "Tracking could not start on $who's phone yet — press Start "
                'tracking again in a minute.',
    };
    return 'Driver changed to $who.$mates $tracking';
  }
}
