import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/route_master.dart';

class RoutesRepository {
  RoutesRepository(this._api);
  final ApiClient _api;

  Future<List<RouteMaster>> list({String? query}) async {
    final rows = await fetchAllPages(_api, '/routes',
        query: {if (query != null && query.isNotEmpty) 'q': query});
    return rows.map(RouteMaster.fromJson).toList();
  }

  Future<RouteMaster> create(RouteMaster r) async {
    final res = await _api.dio.post('/routes', data: r.toJson());
    return RouteMaster.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<RouteMaster> update(RouteMaster r) async {
    final res = await _api.dio.patch(
      '/routes/${r.id}',
      data: r.toJson(),
      options: Options(headers: {'If-Match': r.version.toString()}),
    );
    return RouteMaster.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/routes/$id');
  }
}
