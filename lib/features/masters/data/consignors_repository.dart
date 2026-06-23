import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/consignor.dart';

class ConsignorsRepository {
  ConsignorsRepository(this._api);
  final ApiClient _api;

  Future<List<Consignor>> list({String? query}) async {
    final rows = await fetchAllPages(_api, '/consignors',
        query: {if (query != null && query.isNotEmpty) 'q': query});
    return rows.map(Consignor.fromJson).toList();
  }

  Future<Consignor> create(Consignor c) async {
    final res = await _api.dio.post('/consignors', data: c.toJson());
    return Consignor.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<Consignor> update(Consignor c) async {
    final res = await _api.dio.patch(
      '/consignors/${c.id}',
      data: c.toJson(),
      options: Options(headers: {'If-Match': c.version.toString()}),
    );
    return Consignor.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/consignors/$id');
  }
}
