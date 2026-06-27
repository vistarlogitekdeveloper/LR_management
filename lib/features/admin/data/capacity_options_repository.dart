import '../../../core/network/api_client.dart';

/// One admin-managed Vehicle Capacity option (a tenant-scoped VEHICLE_CAPACITY
/// lookup value). The LR form's capacity dropdown is built from these.
class CapacityOption {
  final String id;
  final String code;
  final String label;
  final int sortOrder;
  const CapacityOption({
    required this.id,
    required this.code,
    required this.label,
    this.sortOrder = 0,
  });

  factory CapacityOption.fromJson(Map<String, dynamic> j) => CapacityOption(
    id: j['id'] as String,
    code: (j['code'] as String?) ?? '',
    label: (j['label'] as String?) ?? '',
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class CapacityOptionsRepository {
  CapacityOptionsRepository(this._api);
  final ApiClient _api;
  static const _cat = 'VEHICLE_CAPACITY';

  Future<List<CapacityOption>> list() async {
    final res = await _api.dio.get('/lookups/manage/$_cat');
    final rows = (res.data['data'] as List?) ?? const [];
    return rows
        .map((e) => CapacityOption.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> create(String label) async {
    await _api.dio.post('/lookups/manage/$_cat', data: {'label': label});
  }

  Future<void> update(String id, String label) async {
    await _api.dio.patch('/lookups/manage/options/$id', data: {'label': label});
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/lookups/manage/options/$id');
  }
}
