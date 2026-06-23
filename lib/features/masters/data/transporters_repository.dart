import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/transporter.dart';

class TransportersRepository {
  TransportersRepository(this._api);
  final ApiClient _api;

  Future<List<Transporter>> list({String? query}) async {
    final rows = await fetchAllPages(_api, '/transporters',
        query: {if (query != null && query.isNotEmpty) 'q': query});
    return rows.map(Transporter.fromJson).toList();
  }

  Future<Transporter> create(Transporter t) async {
    final res = await _api.dio.post('/transporters', data: t.toJson());
    return Transporter.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Transporter> update(Transporter t) async {
    final res = await _api.dio.patch(
      '/transporters/${t.id}',
      data: t.toJson(),
      options: Options(headers: {'If-Match': t.version.toString()}),
    );
    return Transporter.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/transporters/$id');
  }
}
