import '../../../core/network/api_client.dart';
import 'lookup_value.dart';

class LookupsRepository {
  LookupsRepository(this._api);
  final ApiClient _api;

  Future<Map<String, List<LookupValue>>> fetch(List<String> categories) async {
    final res = await _api.dio.get(
      '/lookups',
      queryParameters: {'categories': categories.join(',')},
    );
    final raw = (res.data['data'] as List).cast<Map<String, dynamic>>();
    final all = raw.map(LookupValue.fromJson).toList();
    final grouped = <String, List<LookupValue>>{};
    for (final v in all) {
      grouped.putIfAbsent(v.category, () => []).add(v);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return grouped;
  }
}
