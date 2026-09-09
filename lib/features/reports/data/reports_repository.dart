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
    final totals =
        (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
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

/// One field the import changed (or would change) on an LR.
class MisImportChange {
  /// The sheet's column header, e.g. `Vistar Bill No`.
  final String field;

  /// Previous value, `null` when the field was empty.
  final String? from;
  final String to;

  const MisImportChange({required this.field, this.from, required this.to});

  factory MisImportChange.fromJson(Map<String, dynamic> j) => MisImportChange(
    field: '${j['field'] ?? ''}',
    from: j['from'] == null ? null : '${j['from']}',
    to: '${j['to'] ?? ''}',
  );

  String get summary =>
      '$field: ${from == null || from!.isEmpty ? '—' : from} → $to';
}

/// A single sheet row the import touched, skipped or could not read.
class MisImportRow {
  /// 1-based Excel row number, so the user can jump straight to it.
  final int row;
  final String lrNo;
  final List<MisImportChange> changes;

  /// Set for rows in the `errors` list; null otherwise.
  final String? message;

  const MisImportRow({
    required this.row,
    required this.lrNo,
    this.changes = const [],
    this.message,
  });

  factory MisImportRow.fromJson(Map<String, dynamic> j) => MisImportRow(
    row: (j['row'] as num?)?.toInt() ?? 0,
    lrNo: '${j['lr_no'] ?? ''}',
    changes: ((j['changes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MisImportChange.fromJson(e.cast<String, dynamic>()))
        .toList(),
    message: j['message'] == null ? null : '${j['message']}',
  );
}

/// Outcome of uploading a filled-in MIS workbook. The same shape comes back
/// from a dry run (nothing written, `updated` = what *would* be written) and a
/// real run, so the confirmation preview and the result can share one renderer.
class MisImportResult {
  final bool dryRun;

  /// Editable columns found in the sheet, and any the caller's permissions made
  /// the server ignore (e.g. the bill columns without VIEW_CUSTOMER_RATE).
  final List<String> columns;
  final List<String> ignoredColumns;

  final int rowsRead;
  final int rowsWithValues;
  final int updatedCount;
  final int unchangedCount;
  final int notFoundCount;
  final int errorCount;

  /// Capped at 200 entries each by the server — the counts above are complete.
  final List<MisImportRow> updated;
  final List<MisImportRow> notFound;
  final List<MisImportRow> errors;

  const MisImportResult({
    this.dryRun = false,
    this.columns = const [],
    this.ignoredColumns = const [],
    this.rowsRead = 0,
    this.rowsWithValues = 0,
    this.updatedCount = 0,
    this.unchangedCount = 0,
    this.notFoundCount = 0,
    this.errorCount = 0,
    this.updated = const [],
    this.notFound = const [],
    this.errors = const [],
  });

  factory MisImportResult.fromJson(Map<String, dynamic> j) {
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;
    List<String> strs(dynamic v) =>
        ((v as List?) ?? const []).map((e) => '$e').toList();
    List<MisImportRow> rows(dynamic v) => ((v as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MisImportRow.fromJson(e.cast<String, dynamic>()))
        .toList();
    return MisImportResult(
      dryRun: j['dry_run'] == true,
      columns: strs(j['columns']),
      ignoredColumns: strs(j['ignored_columns']),
      rowsRead: n(j['rows_read']),
      rowsWithValues: n(j['rows_with_values']),
      updatedCount: n(j['updated_count']),
      unchangedCount: n(j['unchanged_count']),
      notFoundCount: n(j['not_found_count']),
      errorCount: n(j['error_count']),
      updated: rows(j['updated']),
      notFound: rows(j['not_found']),
      errors: rows(j['errors']),
    );
  }

  /// Nothing to write — used to skip the confirm step after a dry run.
  bool get hasWork => updatedCount > 0;
}

class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Future<DashboardSummary> dashboard() async {
    final res = await _api.dio.get('/reports/dashboard');
    return DashboardSummary.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
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

  /// Uploads a filled-in MIS workbook so the Accounts-owned columns in it —
  /// Balance Paid Date, Vistar Bill No, Vistar Bill Date — are written back
  /// onto the matching LRs (matched on the sheet's `LR No` column). Everything
  /// else in the sheet is read-only and ignored.
  ///
  /// A BLANK cell means "leave as-is", never "clear": the download blanks cells
  /// the user isn't allowed to see, so clearing on blank would let a restricted
  /// user wipe billing data by re-uploading their own download.
  ///
  /// With [dryRun] true the server parses and diffs but writes nothing, and
  /// returns the identical summary — used to show a confirmation preview.
  Future<MisImportResult> importMisXlsx({
    required List<int> bytes,
    required String filename,
    bool dryRun = false,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ),
    });
    try {
      final res = await _api.dio.post(
        '/reports/mis/import',
        data: form,
        queryParameters: {if (dryRun) 'dry_run': 'true'},
      );
      return MisImportResult.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      // The server explains exactly what's wrong with a rejected sheet ("no LR
      // No column", "larger than 20 MB", …) and that text is what the user
      // needs. Rethrow the mapped ApiException so friendlyErrorMessage renders
      // it, instead of Dio's wrapper stringifying into a stack dump.
      throw e.error ?? e;
    }
  }

  /// Fetches the server-generated Profit & Loss workbook (`.xlsx`) as raw bytes.
  ///
  /// Precedence (highest first): a custom inclusive [from]/[to] range
  /// (`YYYY-MM-DD`, both required together) → [month] (`YYYY-MM`) → [year]
  /// (`YYYY`, financial year Apr Y – Mar Y+1). A range spanning more than one
  /// calendar month also yields the per-month detail sheets. [regionId]
  /// restricts to a region. Only non-empty values are sent, so the backend
  /// applies its own defaults.
  Future<List<int>> profitLossXlsx({
    String? regionId,
    String? month,
    String? year,
    String? from,
    String? to,
  }) async {
    final res = await _api.dio.get(
      '/reports/profit-loss.xlsx',
      queryParameters: {
        if (regionId != null && regionId.isNotEmpty) 'region_id': regionId,
        if (month != null && month.isNotEmpty) 'month': month,
        if (year != null && year.isNotEmpty) 'year': year,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return (res.data as List).cast<int>();
  }
}
