import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/party.dart';

class PartiesRepository {
  PartiesRepository(this._api);
  final ApiClient _api;

  Future<List<Party>> list({String? query}) async {
    final rows = await fetchAllPages(
      _api,
      '/parties',
      query: {if (query != null && query.isNotEmpty) 'q': query},
    );
    return rows.map(Party.fromJson).toList();
  }

  Future<Party> create(Party p) async {
    final res = await _api.dio.post('/parties', data: p.toJson());
    return Party.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Party> update(Party p) async {
    final res = await _api.dio.patch(
      '/parties/${p.id}',
      data: p.toJson(),
      options: Options(headers: {'If-Match': p.version.toString()}),
    );
    return Party.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/parties/$id');
  }
}
