import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';

/// One geocoding search result (Nominatim) — already carries coordinates, so
/// selecting it needs no second round-trip.
class MapsSuggestion {
  final String placeId;
  final String text;
  final double lat;
  final double lng;
  const MapsSuggestion({
    required this.placeId,
    required this.text,
    required this.lat,
    required this.lng,
  });
}

/// Thin client over our backend `/maps` proxy (free OpenStreetMap / Nominatim —
/// no API key). Never talks to the geocoder directly.
class MapsRepository {
  MapsRepository(this._api);
  final ApiClient _api;

  Future<List<MapsSuggestion>> autocomplete(String query) async {
    final res = await _api.dio.get(
      '/maps/autocomplete',
      queryParameters: {'q': query},
    );
    final list = (res.data['data']?['suggestions'] as List?) ?? const [];
    return list
        .map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return MapsSuggestion(
            placeId: (m['place_id'] as String?) ?? '',
            text: (m['text'] as String?) ?? '',
            lat: (m['lat'] as num?)?.toDouble() ?? 0,
            lng: (m['lng'] as num?)?.toDouble() ?? 0,
          );
        })
        .where((s) => s.text.isNotEmpty)
        .toList();
  }

  /// Reverse-geocode a moved map pin to a human address.
  Future<String> reverse(double lat, double lng) async {
    final res = await _api.dio.get(
      '/maps/reverse',
      queryParameters: {'lat': lat, 'lng': lng},
    );
    final m = (res.data['data'] as Map).cast<String, dynamic>();
    return (m['address'] as String?) ?? '';
  }
}

final mapsRepositoryProvider = Provider<MapsRepository>(
  (ref) => MapsRepository(ref.watch(apiClientProvider)),
);
