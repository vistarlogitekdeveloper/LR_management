import 'api_client.dart';

/// Walks a cursor-paginated list endpoint and returns every row. The backend
/// envelope is `{ success, data: [...], meta: { next_cursor } }`.
Future<List<Map<String, dynamic>>> fetchAllPages(
  ApiClient api,
  String path, {
  Map<String, dynamic>? query,
  int pageSize = 100,
  int maxPages = 100,
}) async {
  final rows = <Map<String, dynamic>>[];
  String? cursor;
  var pages = 0;
  do {
    final res = await api.dio.get(path, queryParameters: {
      'limit': pageSize,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      ...?query,
    });
    final data = (res.data['data'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    rows.addAll(data);
    final meta = res.data['meta'];
    cursor = meta is Map ? meta['next_cursor'] as String? : null;
    pages++;
  } while (cursor != null && cursor.isNotEmpty && pages < maxPages);
  return rows;
}
