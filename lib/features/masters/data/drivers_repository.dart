import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/driver.dart';

class DriversRepository {
  DriversRepository(this._api);
  final ApiClient _api;

  Future<List<Driver>> list({String? query}) async {
    final rows = await fetchAllPages(_api, '/drivers',
        query: {if (query != null && query.isNotEmpty) 'q': query});
    return rows.map(Driver.fromJson).toList();
  }

  Future<Driver> create(Driver d) async {
    final res = await _api.dio.post('/drivers', data: d.toJson());
    return Driver.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Driver> update(Driver d) async {
    final res = await _api.dio.patch(
      '/drivers/${d.id}',
      data: d.toJson(),
      options: Options(headers: {'If-Match': d.version.toString()}),
    );
    return Driver.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/drivers/$id');
  }
}
