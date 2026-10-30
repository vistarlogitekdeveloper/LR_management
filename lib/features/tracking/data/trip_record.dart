import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/lr_models.dart';
import 'trip_history.dart';

/// One finished trip on the History tab (server: GET /tracking/history,
/// 30 Oct 2026): the LR, how it ended, and what happened on the road.
class TripRecord {
  final String lrId;
  final String number;
  final LrStatus outcome;
  final bool isSpecial;
  final String truck;
  final String driver;
  final String fromCity;
  final String toCity;
  final String consignor;
  final String consignee;
  final String regionCode;
  final DateTime? lrDate;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final double? tripHours;
  final double? routeKm;
  final int halts;
  final double haltHours;
  final double longestHaltHours;
  final bool haltAlerted;
  final int driverChanges;
  final int fixes;
  final bool tracked;

  /// Built from the LR list (an older server without /tracking/history): no
  /// trip numbers to show.
  final bool hasMetrics;

  const TripRecord({
    required this.lrId,
    required this.number,
    required this.outcome,
    this.isSpecial = false,
    this.truck = '',
    this.driver = '',
    this.fromCity = '',
    this.toCity = '',
    this.consignor = '',
    this.consignee = '',
    this.regionCode = '',
    this.lrDate,
    this.startedAt,
    this.endedAt,
    this.tripHours,
    this.routeKm,
    this.halts = 0,
    this.haltHours = 0,
    this.longestHaltHours = 0,
    this.haltAlerted = false,
    this.driverChanges = 0,
    this.fixes = 0,
    this.tracked = false,
    this.hasMetrics = true,
  });

  factory TripRecord.fromJson(Map<String, dynamic> j) {
    DateTime? dt(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    double? num0(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    String s(Object? v) => (v ?? '').toString();
    return TripRecord(
      lrId: s(j['lr_id']),
      number: s(j['lr_number']),
      outcome: j['outcome'] == 'CANCELLED'
          ? LrStatus.cancelled
          : LrStatus.delivered,
      isSpecial: j['is_special_vehicle'] == true,
      truck: s(j['truck_number']),
      driver: s(j['driver_name']),
      fromCity: s(j['from_city']),
      toCity: s(j['to_city']),
      consignor: s(j['consignor_name']),
      consignee: s(j['consignee_name']),
      regionCode: s(j['region_code']),
      lrDate: dt(j['lr_date']),
      startedAt: dt(j['started_at']),
      endedAt: dt(j['ended_at']),
      tripHours: num0(j['trip_hours']),
      routeKm: num0(j['route_km']),
      halts: (j['halts'] as num?)?.toInt() ?? 0,
      haltHours: num0(j['halt_hours']) ?? 0,
      longestHaltHours: num0(j['longest_halt_hours']) ?? 0,
      haltAlerted: j['halt_alerted'] == true,
      driverChanges: (j['driver_changes'] as num?)?.toInt() ?? 0,
      fixes: (j['fixes'] as num?)?.toInt() ?? 0,
      tracked: j['tracked'] == true,
    );
  }

  factory TripRecord.fromLr(LorryReceipt lr) => TripRecord(
    lrId: lr.id,
    number: lr.number,
    outcome: lr.status,
    isSpecial: lr.isSpecialVehicle,
    truck: lr.vehicle.number,
    driver: lr.tripDriverName,
    fromCity: lr.fromCity,
    toCity: lr.toCity,
    consignor: lr.consignor.name,
    consignee: lr.consignee.name,
    lrDate: lr.date,
    hasMetrics: false,
  );

  /// The date the list shows: when the trip ended, else the LR date.
  DateTime? get shownDate => endedAt ?? lrDate;
}

/// GET /tracking/history. Null when the server has no such endpoint yet (404),
/// so the History tab can fall back to the LR list.
class TripHistoryRepository {
  TripHistoryRepository(this._api);
  final ApiClient _api;

  Future<List<TripRecord>?> history(
    TripHistoryFilter f, {
    DateTime? now,
  }) async {
    final cutoff = f.period.cutoff(now ?? DateTime.now());
    try {
      final res = await _api.dio.get(
        '/tracking/history',
        queryParameters: {
          if (cutoff != null) 'from': cutoff.toIso8601String().substring(0, 10),
          if (f.status == LrStatus.delivered) 'outcome': 'delivered',
          if (f.status == LrStatus.cancelled) 'outcome': 'cancelled',
          if (f.specialOnly) 'special': true,
          if (f.hasHalts) 'has_halts': true,
          'limit': 1000,
        },
      );
      return (res.data['data'] as List)
          .whereType<Map>()
          .map((m) => TripRecord.fromJson(m.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}

/// The search box over server rows (instant, no request), and the Active-tab
/// exclusion. The server already applied period / outcome / special / halts.
List<TripRecord> filterTripRecords(
  List<TripRecord> all, {
  String query = '',
  Set<String> excludeLrIds = const {},
}) {
  final q = query.trim().toLowerCase();
  return all.where((t) {
    if (excludeLrIds.contains(t.lrId)) return false;
    if (q.isEmpty) return true;
    return [
      t.number,
      t.truck,
      t.driver,
      t.fromCity,
      t.toCity,
      t.consignor,
      t.consignee,
    ].join(' ').toLowerCase().contains(q);
  }).toList();
}
