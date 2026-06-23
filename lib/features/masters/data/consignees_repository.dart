import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/consignee.dart';

class ConsigneesRepository {
  ConsigneesRepository(this._api);
  final ApiClient _api;

  Future<List<Consignee>> list({String? query}) async {
    final rows = await fetchAllPages(_api, '/consignees',
        query: {if (query != null && query.isNotEmpty) 'q': query});
    return rows.map(Consignee.fromJson).toList();
  }

  Future<Consignee> create(Consignee c) async {
    final res = await _api.dio.post('/consignees', data: c.toJson());
    return Consignee.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Consignee> update(Consignee c) async {
    final res = await _api.dio.patch(
      '/consignees/${c.id}',
      data: c.toJson(),
      options: Options(headers: {'If-Match': c.version.toString()}),
    );
    return Consignee.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/consignees/$id');
  }
}
