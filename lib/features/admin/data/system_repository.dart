import 'dart:async';

import '../../../core/network/api_client.dart';
import 'system_config.dart';

class SystemRepository {
  SystemRepository(this._api);
  final ApiClient _api;

  /// Loads LR numbering + print format from the backend and merges them into a
  /// single SystemConfig (security/backup fields keep their local defaults —
  /// the backend has no dedicated columns for them yet).
  Future<SystemConfig> getConfig() async {
    final results = await Future.wait([
      _api.dio.get('/system/numbering'),
      _api.dio.get('/system/lr-format'),
    ]);
    final numbering =
        (results[0].data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final format =
        (results[1].data['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    const def = SystemConfig();
    return def.copyWith(
      lrPrefix: numbering['prefix'] as String?,
      lrFormat: numbering['format_template'] as String?,
      nextLrNumber:
          int.tryParse('${numbering['next_sequence'] ?? ''}') ?? def.nextLrNumber,
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

  Future<void> saveNumbering(SystemConfig cfg) async {
    await _api.dio.patch('/system/numbering', data: {
      'prefix': cfg.lrPrefix,
      'format_template': cfg.lrFormat,
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
