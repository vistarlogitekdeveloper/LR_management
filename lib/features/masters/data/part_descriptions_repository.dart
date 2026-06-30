import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/part_description.dart';

class PartDescriptionsRepository {
  PartDescriptionsRepository(this._api);
  final ApiClient _api;

  Future<List<PartDescription>> list(
      {String? query, bool activeOnly = false}) async {
    final rows = await fetchAllPages(_api, '/part-descriptions', query: {
      if (query != null && query.isNotEmpty) 'q': query,
      if (activeOnly) 'active': 'true',
    });
    return rows.map(PartDescription.fromJson).toList();
  }

  Future<PartDescription> create(PartDescription p) async {
    final res = await _api.dio.post('/part-descriptions', data: p.toJson());
    return PartDescription.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<PartDescription> update(PartDescription p) async {
    final res = await _api.dio.patch(
      '/part-descriptions/${p.id}',
      data: p.toJson(),
      options: Options(headers: {'If-Match': p.version.toString()}),
    );
    return PartDescription.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/part-descriptions/$id');
  }
}
