import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/vehicle.dart';

class VehiclesRepository {
  VehiclesRepository(this._api);
  final ApiClient _api;

  Future<List<Vehicle>> list({String? query}) async {
    final rows = await fetchAllPages(_api, '/vehicles',
        query: {if (query != null && query.isNotEmpty) 'q': query});
    return rows.map(Vehicle.fromJson).toList();
  }

  Future<Vehicle> create(Vehicle v) async {
    final res = await _api.dio.post('/vehicles', data: v.toJson());
    return Vehicle.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Vehicle> update(Vehicle v) async {
    final res = await _api.dio.patch(
      '/vehicles/${v.id}',
      data: v.toJson(),
      options: Options(headers: {'If-Match': v.version.toString()}),
    );
    return Vehicle.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/vehicles/$id');
  }
}
