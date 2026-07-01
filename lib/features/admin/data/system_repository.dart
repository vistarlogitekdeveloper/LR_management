import 'dart:async';

import '../../../core/network/api_client.dart';
import 'system_config.dart';

class SystemRepository {
  SystemRepository(this._api);
  final ApiClient _api;

  /// Loads LR numbering + print format from the backend and merges them into a
  /// single SystemConfig (security/backup fields keep their local defaults —
  /// the backend has no dedicated columns for them yet).
  Future<SystemConfig> getConfig({String? regionId}) async {
    final results = await Future.wait([
      _api.dio.get('/system/numbering'),
      _api.dio.get('/system/lr-format'),
    ]);
    // /system/numbering now returns an ARRAY of rows (one per region + an
    // optional tenant-wide fallback row with region_id == null). Pick the row
    // for the caller's region; fall back to the region-less row.
    final numbering = _pickNumberingRow(results[0].data['data'], regionId);
    final format =
        (results[1].data['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    final region = numbering['region'];
    final regionCode = region is Map
        ? (region['short_code'] as String?) ?? ''
        : (numbering['region_short_code'] as String?) ??
            (numbering['short_code'] as String?) ??
            '';
    final regionName = region is Map
        ? (region['name'] as String?) ?? ''
        : (numbering['region_name'] as String?) ?? '';

    const def = SystemConfig();
    return def.copyWith(
      lrPrefix: numbering['prefix'] as String?,
      lrFormat: numbering['format_template'] as String?,
      nextLrNumber:
          int.tryParse('${numbering['next_sequence'] ?? ''}') ?? def.nextLrNumber,
      lrRegionId: numbering['region_id'] as String?,
      lrRegionCode: regionCode,
      lrRegionName: regionName,
      lrResetPeriod: numbering['reset_period'] as String?,
      companyName: format['company_name'] as String?,
      companyTagline: format['tagline'] as String?,
      // Optional — backend has no column yet; falls back to the default
      // (the Vistar registered address / GSTIN shown on the consignment note).
      companyAddress: format['company_address'] as String?,
      companyGstin: format['company_gstin'] as String?,
      termsText: format['terms_md'] as String?,
      footerText: format['footer_md'] as String?,
      showEwb: format['show_ewb'] as bool?,
      showInsurance: format['show_insurance'] as bool?,
      showMathadi: format['show_mathadi'] as bool?,
      showVistarMargin: format['show_vistar_margin'] as bool?,
    );
  }

  /// Picks the numbering row matching [regionId] from the array response; falls
  /// back to the tenant-wide row (region_id == null) and then the first row.
  /// Tolerates a legacy single-object response too.
  Map<String, dynamic> _pickNumberingRow(dynamic data, String? regionId) {
    final rows = <Map<String, dynamic>>[];
    if (data is List) {
      for (final r in data) {
        if (r is Map) rows.add(r.cast<String, dynamic>());
      }
    } else if (data is Map) {
      rows.add(data.cast<String, dynamic>());
    }
    if (rows.isEmpty) return const {};
    for (final r in rows) {
      if (r['region_id'] == regionId) return r;
    }
    for (final r in rows) {
      if (r['region_id'] == null) return r;
    }
    return rows.first;
  }

  Future<void> saveNumbering(SystemConfig cfg) async {
    await _api.dio.patch('/system/numbering', data: {
      'prefix': cfg.lrPrefix,
      'format_template': cfg.lrFormat,
      // Which row to edit — null targets the tenant-wide fallback row.
      'region_id': cfg.lrRegionId,
    });
  }

  Future<void> saveFormat(SystemConfig cfg) async {
    await _api.dio.patch('/system/lr-format', data: {
      'company_name': cfg.companyName,
      'tagline': cfg.companyTagline,
      'terms_md': cfg.termsText,
      'footer_md': cfg.footerText,
      'show_ewb': cfg.showEwb,
      'show_insurance': cfg.showInsurance,
      'show_mathadi': cfg.showMathadi,
      'show_vistar_margin': cfg.showVistarMargin,
    });
  }
}
