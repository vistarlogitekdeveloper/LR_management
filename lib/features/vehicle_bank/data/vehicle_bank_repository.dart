import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/paginate.dart';
import 'vehicle_bank_models.dart';

/// One page of the directory, plus the token for the next one.
class VehicleBankPage {
  final List<VehicleBankRow> rows;

  /// Opaque — pass it back untouched; the server owns its shape. Null on the
  /// last page.
  final String? nextCursor;

  const VehicleBankPage({this.rows = const [], this.nextCursor});

  bool get hasMore {
    final c = nextCursor;
    return c != null && c.isNotEmpty;
  }
}

/// Read-only access to the Vehicle Bank: one row per vehicle with its
/// transporter, driver and route joined on.
///
/// There is no create/update/delete here by design — editing stays in the
/// master screens so this data keeps exactly one write path.
class VehicleBankRepository {
  VehicleBankRepository(this._api);
  final ApiClient _api;

  static const String _listPath = '/vehicle-bank';
  static const String _exportPath = '/vehicle-bank/export.xlsx';

  /// Server default; also what `meta.limit` reports when we send none.
  static const int defaultPageSize = 50;

  /// Server ceiling (Joi clamps above this).
  static const int maxPageSize = 200;

  /// The export's own cap. Walking more pages than this would build a list the
  /// export itself would refuse to produce.
  static const int maxRows = 10000;

  /// One page. [cursor] must be the token exactly as `meta.next_cursor`
  /// delivered it.
  Future<VehicleBankPage> list(
    VehicleBankFilter filter, {
    int limit = defaultPageSize,
    String? cursor,
  }) async {
    try {
      final res = await _api.dio.get(
        _listPath,
        queryParameters: {
          ...filter.toQueryParameters(),
          'limit': limit.clamp(1, maxPageSize),
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      );
      final data = (res.data['data'] as List?) ?? const [];
      final meta = res.data['meta'];
      return VehicleBankPage(
        rows: data
            .whereType<Map>()
            .map((e) => VehicleBankRow.fromJson(e.cast<String, dynamic>()))
            .toList(),
        nextCursor: meta is Map ? meta['next_cursor'] as String? : null,
      );
    } on DioException catch (e) {
      // The interceptor parks the parsed backend error on DioException.error;
      // rethrow that so the operator sees "Missing permission: …" rather than
      // Dio's wrapper stringified into a wall of text.
      throw e.error ?? e;
    }
  }

  /// Every matching row, walking the cursor to the end. The directory is a
  /// fleet-sized list (hundreds, not millions) and the screen filters, sorts
  /// and exports across the whole set, so it is fetched whole rather than
  /// page-by-page — with the same ceiling the export uses.
  Future<List<VehicleBankRow>> listAll(VehicleBankFilter filter) async {
    try {
      final rows = await fetchAllPages(
        _api,
        _listPath,
        query: filter.toQueryParameters(),
        pageSize: maxPageSize,
        maxPages: maxRows ~/ maxPageSize,
      );
      return rows.map(VehicleBankRow.fromJson).toList();
    } on DioException catch (e) {
      throw e.error ?? e;
    }
  }

  /// The server-generated workbook as raw bytes, for the platform file opener.
  ///
  /// Same filters as [list], and the same masked/rate-free columns — the
  /// workbook is built from the same service, so it can never carry more than
  /// the screen shows. Unpaged, capped at [maxRows] rows server-side.
  Future<List<int>> exportXlsx(VehicleBankFilter filter) async {
    try {
      final res = await _api.dio.get(
        _exportPath,
        queryParameters: filter.toQueryParameters(),
        options: Options(responseType: ResponseType.bytes),
      );
      return (res.data as List).cast<int>();
    } on DioException catch (e) {
      throw _exportFailure(e);
    }
  }

  /// A failed export answers with a JSON envelope, but the request asked for
  /// bytes — so `response.data` is a byte list and the interceptor's Map-shaped
  /// mapping never ran, leaving a generic "something went wrong". Decode the
  /// body here to recover the server's actual message (permission, validation).
  Object _exportFailure(DioException e) {
    final body = e.response?.data;
    if (body is List<int> && body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
        if (decoded is Map) {
          return ApiException(
            status: e.response?.statusCode ?? 0,
            code: decoded['code']?.toString() ?? 'NETWORK_ERROR',
            message:
                decoded['error']?.toString() ??
                decoded['message']?.toString() ??
                friendlyErrorMessage(e),
            traceId: decoded['traceId']?.toString(),
            details: decoded,
          );
        }
      } on FormatException {
        // Not JSON after all (a truncated or genuinely binary body) — fall
        // through to the interceptor's mapped error, which is still readable.
      }
    }
    return e.error ?? e;
  }
}
