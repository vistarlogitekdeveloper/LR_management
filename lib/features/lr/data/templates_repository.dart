import '../../../core/network/api_client.dart';
import '../../../shared/models/lr_template.dart';

class TemplatesRepository {
  TemplatesRepository(this._api);
  final ApiClient _api;

  Future<List<LrTemplate>> list() async {
    final res = await _api.dio.get('/lr-templates');
    final rows = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return rows.map(LrTemplate.fromJson).toList();
  }

  Future<LrTemplate> create(String title, Map<String, dynamic> payload) async {
    final res = await _api.dio
        .post('/lr-templates', data: {'title': title, 'payload': payload});
    return LrTemplate.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<LrTemplate> update(
    String id, {
    String? title,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.dio.patch('/lr-templates/$id', data: {
      if (title != null) 'title': title,
      if (payload != null) 'payload': payload,
    });
    return LrTemplate.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/lr-templates/$id');
  }
}
