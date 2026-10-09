import 'tracking_repository.dart';

/// Which running trips the Live Tracking map shows.
enum FleetScope {
  /// Actually on the road: a fix within 24 h, or a trip under a day old still
  /// waiting for its first fix. The default, and the "Active trips" count.
  live,

  /// Standing in one spot (within ~2 km) for 10 h or more — the halt alert.
  halted,

  /// Running trips with nothing for over a day — the ones to close.
  noSignal,

  /// Live or not, the driver has not approved SIM consent yet.
  consentPending,

  /// Every running trip.
  all,
}

extension FleetScopeX on FleetScope {
  String get label => switch (this) {
    FleetScope.live => 'Live now',
    FleetScope.halted => 'Halted ${haltAlertHours}h+',
    FleetScope.noSignal => 'No signal 24h+',
    FleetScope.consentPending => 'Consent pending',
    FleetScope.all => 'All running',
  };
}

/// The filter bar's state.
class FleetFilter {
  final FleetScope scope;

  /// Region short code ("PUN"), or null for every region.
  final String? region;

  /// Free text over LR, vehicle, driver and both cities.
  final String query;

  const FleetFilter({
    this.scope = FleetScope.live,
    this.region,
    this.query = '',
  });

  FleetFilter copyWith({
    FleetScope? scope,
    String? region,
    bool clearRegion = false,
    String? query,
  }) => FleetFilter(
    scope: scope ?? this.scope,
    region: clearRegion ? null : (region ?? this.region),
    query: query ?? this.query,
  );
}

bool _isLive(FleetVehicle v) =>
    v.signal == FleetSignal.live || v.signal == FleetSignal.awaiting;

bool _consentPending(FleetVehicle v) =>
    (v.consentStatus ?? '').toUpperCase().contains('PENDING');

bool _inScope(FleetVehicle v, FleetScope scope) => switch (scope) {
  FleetScope.live => _isLive(v),
  FleetScope.halted => v.haltAlert,
  FleetScope.noSignal => v.signal == FleetSignal.noSignal,
  FleetScope.consentPending => _consentPending(v),
  FleetScope.all => true,
};

bool _matches(FleetVehicle v, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return [
    v.lrNumber,
    v.truckNumber,
    v.driverName,
    v.fromCity,
    v.toCity,
    v.location?.city,
  ].any((s) => (s ?? '').toLowerCase().contains(q));
}

/// The trips to show for [filter]. A stopped / ended trip is never shown (an
/// older server still lists them). Newest fix first; trips with no fix after
/// those with one.
List<FleetVehicle> filterFleet(List<FleetVehicle> all, FleetFilter filter) {
  final out = all.where((v) {
    if (v.tripOver) return false;
    if (filter.region != null && v.regionCode != filter.region) return false;
    return _inScope(v, filter.scope) && _matches(v, filter.query);
  }).toList();
  out.sort((a, b) {
    final at = a.location?.at;
    final bt = b.location?.at;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return out;
}

/// How many trips each scope would show, for the chips — counted within the
/// selected region, ignoring the search box.
Map<FleetScope, int> fleetScopeCounts(List<FleetVehicle> all, String? region) {
  final running = all.where(
    (v) => !v.tripOver && (region == null || v.regionCode == region),
  );
  return {
    for (final s in FleetScope.values)
      s: running.where((v) => _inScope(v, s)).length,
  };
}

/// The regions present among running trips, sorted, for the region picker.
List<String> fleetRegions(List<FleetVehicle> all) {
  final codes = {
    for (final v in all)
      if (!v.tripOver && v.regionCode.isNotEmpty) v.regionCode,
  }.toList()..sort();
  return codes;
}
