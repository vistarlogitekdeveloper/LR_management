import '../../../core/network/api_client.dart';
import 'lookup_value.dart';

class LookupsRepository {
  LookupsRepository(this._api);
  final ApiClient _api;

  /// The backend returns `{ data: { CATEGORY: [ {id,code,label,sort_order,meta} ] } }`
  /// — a map keyed by category code, not a flat list. We flatten it into our
  /// `category -> values` map (injecting the category onto each value).
  Future<Map<String, List<LookupValue>>> fetch(List<String> categories) async {
    final res = await _api.dio.get(
      '/lookups',
      queryParameters: {'categories': categories.join(',')},
    );
    final data = res.data['data'];
    final grouped = <String, List<LookupValue>>{};

    if (data is Map) {
      data.forEach((category, list) {
        if (list is List) {
          grouped[category.toString()] = list
              .whereType<Map>()
              .map((e) => LookupValue.fromJson({
                    ...e.cast<String, dynamic>(),
                    'category': category.toString(),
                  }))
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
      });
    } else if (data is List) {
      // Defensive: tolerate a flat-list shape where each value carries its category.
      for (final e in data.whereType<Map>()) {
        final v = LookupValue.fromJson(e.cast<String, dynamic>());
        grouped.putIfAbsent(v.category, () => []).add(v);
      }
      for (final list in grouped.values) {
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
    }

    return grouped;
  }
}
