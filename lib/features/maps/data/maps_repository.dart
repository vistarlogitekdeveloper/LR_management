import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';

/// One place-search result from the backend `/maps` proxy.
///
/// [lat] and [lng] are NULLABLE, and that is the whole reason this class is
/// shaped the way it is. Nominatim returns coordinates with every match, but
/// Google Places Autocomplete does not — resolving a pin there is a second call
/// ([MapsRepository.details]) which is also what closes the billing session. So
/// a suggestion is either already a pin or a promise of one, and the caller has
/// to know which before it moves the map.
///
/// Reading a missing coordinate as 0 is exactly the bug this replaces: 0,0 is a
/// real point in the Gulf of Guinea, so the pin lands there silently instead of
/// failing.
class MapsSuggestion {
  final String placeId;
  final String text;
  final double? lat;
  final double? lng;

  /// Which layer produced this row: `saved_place` (a gate somebody already
  /// picked for a route — ours, and verified), `google`, or `nominatim`. Passed
  /// back on [MapsRepository.details] so the server can answer without spending
  /// an upstream call where it already has the answer.
  final String source;

  const MapsSuggestion({
    required this.placeId,
    required this.text,
    required this.lat,
    required this.lng,
    this.source = '',
  });

  /// True when this row already carries a usable pin and selecting it needs no
  /// second round-trip. (0, 0) is treated as absent for the reason above.
  bool get hasCoords {
    final la = lat;
    final ln = lng;
    if (la == null || ln == null) return false;
    if (la.abs() > 90 || ln.abs() > 180) return false;
    return !(la == 0 && ln == 0);
  }

  /// True when the pin must be fetched with [MapsRepository.details] before the
  /// map can move to it.
  bool get needsResolve => !hasCoords;
}

/// A place resolved to an actual pin.
class PlaceDetails {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
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

/// Thin client over our backend `/maps` proxy. Never talks to a geocoder
/// directly — the API key lives only on the server, and which geocoder answers
/// is the server's decision (`MAPS_PROVIDER`).
class MapsRepository {
  MapsRepository(this._api);
  final ApiClient _api;

  /// Search for a place.
  ///
  /// [sessionToken] groups the keystrokes of ONE search with the
  /// [details] call that ends it. Google bills a search plus its details call as
  /// a single session; without the token every keystroke is billed separately,
  /// which is roughly an order of magnitude more expensive for the same result.
  ///
  /// It is also how this client tells the server it is able to handle a
  /// coordinate-less row at all. A caller that sends no token is deliberately
  /// served from the free provider instead, so an older build can never be
  /// handed a suggestion it would drop at 0,0.
  ///
  /// [lat]/[lng] are the current map centre, used to bias results towards what
  /// the user is looking at. Optional — an absent or unusable pair simply means
  /// no bias.
  Future<List<MapsSuggestion>> autocomplete(
    String query, {
    String? sessionToken,
    double? lat,
    double? lng,
  }) async {
    final res = await _api.dio.get(
      '/maps/autocomplete',
      queryParameters: {
        'q': query,
        if (sessionToken != null && sessionToken.isNotEmpty)
          'session_token': sessionToken,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      },
    );
    final list = (res.data['data']?['suggestions'] as List?) ?? const [];
    return list
        .map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return MapsSuggestion(
            placeId: (m['place_id'] as String?) ?? '',
            text: (m['text'] as String?) ?? '',
            // Deliberately NOT `?? 0` — see the note on MapsSuggestion.
            lat: (m['lat'] as num?)?.toDouble(),
            lng: (m['lng'] as num?)?.toDouble(),
            source: (m['source'] as String?) ?? '',
          );
        })
        .where((s) => s.text.isNotEmpty)
        // A row with neither a pin nor an id can never become one. The server
        // filters these too; this is the client refusing to display something
        // it could not act on if tapped.
        .where((s) => s.hasCoords || s.placeId.isNotEmpty)
        .toList();
  }

  /// Resolve a picked suggestion to a pin.
  ///
  /// [picked] is passed back to the server verbatim. That is not redundant: a
  /// row that already has coordinates is answered from it for free, and a
  /// Nominatim row CANNOT be resolved without it (its place_id is an internal
  /// row id that Nominatim's own lookup cannot key on). Sending it is what makes
  /// this endpoint work on every provider rather than only on Google.
  ///
  /// [sessionToken] must be the SAME token used for the autocomplete calls that
  /// produced [picked] — that is what makes the pair one billable session.
  ///
  /// Returns null when the place cannot be resolved, which the caller shows as
  /// "try another result" rather than moving the pin somewhere wrong.
  Future<PlaceDetails?> details(
    MapsSuggestion picked, {
    String? sessionToken,
  }) async {
    if (picked.placeId.isEmpty) return null;
    try {
      final res = await _api.dio.get(
        '/maps/details',
        queryParameters: {
          'place_id': picked.placeId,
          if (sessionToken != null && sessionToken.isNotEmpty)
            'session_token': sessionToken,
          if (picked.text.isNotEmpty) 'text': picked.text,
          if (picked.lat != null) 'lat': picked.lat,
          if (picked.lng != null) 'lng': picked.lng,
          if (picked.source.isNotEmpty) 'source': picked.source,
        },
      );
      final m = (res.data['data'] as Map?)?.cast<String, dynamic>();
      if (m == null) return null;
      final la = (m['lat'] as num?)?.toDouble();
      final ln = (m['lng'] as num?)?.toDouble();
      // The server should never send an unusable pair here, but this is the
      // last place it could reach the map, so it is checked rather than trusted.
      if (la == null || ln == null) return null;
      if (la.abs() > 90 || ln.abs() > 180 || (la == 0 && ln == 0)) return null;
      return PlaceDetails(
        placeId: (m['place_id'] as String?) ?? picked.placeId,
        name: (m['name'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        lat: la,
        lng: ln,
      );
    } catch (_) {
      return null;
    }
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
