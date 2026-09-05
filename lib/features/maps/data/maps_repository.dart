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

/// Road distance/duration between two points, from the backend OSRM proxy.
class RoadDistance {
  final double distanceKm;
  final int durationMin;
  const RoadDistance({required this.distanceKm, required this.durationMin});
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

  /// Road distance/duration for a route's two pins. Returns null when routing
  /// is unavailable, the request fails, or the response shape is unexpected —
  /// this only ever prefills a field the user can type themselves, so the
  /// caller treats null as "leave the field alone" and shows nothing.
  Future<RoadDistance?> roadDistance({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    try {
      final res = await _api.dio.get(
        '/maps/road-distance',
        queryParameters: {
          'from_lat': fromLat,
          'from_lng': fromLng,
          'to_lat': toLat,
          'to_lng': toLng,
        },
      );
      final data = res.data;
      if (data is! Map) return null;
      final m = (data['data'] as Map?)?.cast<String, dynamic>();
      // available:false is a routing outage, not an error — same silent skip.
      if (m == null || m['available'] != true) return null;
      final km = (m['distance_km'] as num?)?.toDouble();
      if (km == null) return null;
      final mins = (m['duration_min'] as num?)?.round() ?? 0;
      return RoadDistance(distanceKm: km, durationMin: mins);
    } catch (_) {
      return null;
    }
  }
}

final mapsRepositoryProvider = Provider<MapsRepository>(
  (ref) => MapsRepository(ref.watch(apiClientProvider)),
);
