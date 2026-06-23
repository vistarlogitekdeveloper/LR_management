import '../../../core/network/api_client.dart';

class DashboardSummary {
  final int count;
  final double totalFreight;
  final double outstanding;
  final Map<String, int> byStatus; // code -> count
  final List<Map<String, dynamic>> recentLrs;
  final List<Map<String, dynamic>> topConsignors;

  const DashboardSummary({
    this.count = 0,
    this.totalFreight = 0,
    this.outstanding = 0,
    this.byStatus = const {},
    this.recentLrs = const [],
    this.topConsignors = const [],
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
    return DashboardSummary(
      count: num2(totals['count']).toInt(),
      totalFreight: num2(totals['total_freight']),
      outstanding: num2(totals['outstanding']),
      byStatus: byStatus,
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
}
