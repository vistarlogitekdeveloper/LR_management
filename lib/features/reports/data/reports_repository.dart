import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

/// The three scopes every dashboard tile reports. The server computes all of
/// them in IST and already applies region + permission scoping, so these are
/// rendered as-is — never re-aggregated on the client.
class MetricScopes {
  final double today;
  final double mtd;
  final double total;

  const MetricScopes({this.today = 0, this.mtd = 0, this.total = 0});

  factory MetricScopes.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return MetricScopes(
      today: n(json['today']),
      mtd: n(json['mtd']),
      total: n(json['total']),
    );
  }
}

class DashboardSummary {
  final int count;
  final double totalFreight;
  final double outstanding;
  final Map<String, int> byStatus; // code -> count
  final List<Map<String, dynamic>> recentLrs;
  final List<Map<String, dynamic>> topConsignors;

  /// Per-tile today/mtd/total figures, keyed by metric code (`lrs_booked`,
  /// `vehicles_placed`, `vehicles_dispatched`, `trips_in_transit`,
  /// `trips_completed`, `pending_delivery`, `pending_freight`).
  ///
  /// Empty when the app is talking to a backend that predates the metrics
  /// payload — the dashboard falls back to deriving the tiles locally, so a
  /// deploy-order skew degrades the numbers rather than emptying the screen.
  ///
  /// A metric can also be absent because the viewer lacks the permission for
  /// it: the server drops `pending_freight` entirely without
  /// VIEW_TRANSPORTER_RATE rather than sending zeroes.
  final Map<String, MetricScopes> metrics;

  const DashboardSummary({
    this.count = 0,
    this.totalFreight = 0,
    this.outstanding = 0,
    this.byStatus = const {},
    this.recentLrs = const [],
    this.topConsignors = const [],
    this.metrics = const {},
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    double num2(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    final totals = (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final byStatus = <String, int>{};
    for (final row in (json['by_status'] as List?) ?? const []) {
      if (row is Map) {
        final m = row.cast<String, dynamic>();
        final nestedStatus = m['status'];
        final code = nestedStatus is Map ? nestedStatus['code'] : null;
        final key =
            (code ?? m['code'] ?? m['status_code'] ?? m['status_id'] ?? '')
                .toString();
        final c = num2(m['count']).toInt();
        if (key.isNotEmpty) byStatus[key] = c;
      }
    }
    final metrics = <String, MetricScopes>{};
    for (final e in ((json['metrics'] as Map?) ?? const {}).entries) {
      final v = e.value;
      if (v is Map) {
        metrics['${e.key}'] = MetricScopes.fromJson(v.cast<String, dynamic>());
      }
    }

    return DashboardSummary(
      count: num2(totals['count']).toInt(),
      totalFreight: num2(totals['total_freight']),
      outstanding: num2(totals['outstanding']),
      byStatus: byStatus,
      metrics: metrics,
      recentLrs: ((json['recent_lrs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
      topConsignors: ((json['top_consignors'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
    );
  }
}

class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Future<DashboardSummary> dashboard() async {
    final res = await _api.dio.get('/reports/dashboard');
    return DashboardSummary.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  /// Fetches the server-generated MIS workbook (`.xlsx`) as raw bytes. Optional
  /// `from`/`to` are `YYYY-MM-DD` LR-date bounds.
  ///
  /// [sentForPayment] filters by Accounts' "sent for advance" stage:
  ///   `true`  → only LRs already sent for payment,
  ///   `false` → only LRs not yet sent (still pending),
  ///   `null`  → all LRs (the default).
  /// It is only sent when non-null, so the backend treats absence as "all".
  Future<List<int>> misXlsx({
    String? from,
    String? to,
    String? regionId,
    String? createdBy,
    bool? sentForPayment,
  }) async {
    final res = await _api.dio.get(
      '/reports/mis.xlsx',
      queryParameters: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (regionId != null && regionId.isNotEmpty) 'region_id': regionId,
        if (createdBy != null && createdBy.isNotEmpty) 'created_by': createdBy,
        'sent_for_payment': ?sentForPayment,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return (res.data as List).cast<int>();
  }
}
