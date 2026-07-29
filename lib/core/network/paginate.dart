import 'api_client.dart';

/// Walks a cursor-paginated list endpoint and returns every row. The backend
/// envelope is `{ success, data: [...], meta: { next_cursor } }`.
///
/// [firstPageSize] (when set) sizes only the FIRST request — a small first page
/// lets a screen paint quickly, then [pageSize] pulls the rest in bulk. [onPage]
/// fires with each page's rows as they arrive (including an empty final/only
/// page), so callers can render progressively instead of waiting for the whole
/// set. The full accumulated list is still returned.
Future<List<Map<String, dynamic>>> fetchAllPages(
  ApiClient api,
  String path, {
  Map<String, dynamic>? query,
  int pageSize = 100,
  int? firstPageSize,
  int maxPages = 100,
  void Function(List<Map<String, dynamic>> pageRows)? onPage,
}) async {
  final rows = <Map<String, dynamic>>[];
  String? cursor;
  var pages = 0;
  do {
    final size = (pages == 0 && firstPageSize != null) ? firstPageSize : pageSize;
    final res = await api.dio.get(path, queryParameters: {
      'limit': size,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      ...?query,
    });
    final data = (res.data['data'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    rows.addAll(data);
    // Emit every page — including an empty first/only page — so a progressive
    // consumer clears stale rows on an empty result rather than keeping them.
    onPage?.call(data);
    final meta = res.data['meta'];
    cursor = meta is Map ? meta['next_cursor'] as String? : null;
    pages++;
  } while (cursor != null && cursor.isNotEmpty && pages < maxPages);
  return rows;
}
