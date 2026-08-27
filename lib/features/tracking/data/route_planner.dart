import 'package:latlong2/latlong.dart';

/// One drivable route option between two points, as returned by the backend
/// /tracking/lr/:id/route endpoint. The backend sends plain [lat, lng] pairs
/// (GeoJSON), so there is NO client-side polyline decoding — that was unreliable
/// on Flutter web (dart2js) and produced empty/garbage routes.
class RouteOption {
  final String kind; // 'fastest' | 'shortest'
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  const RouteOption({
    required this.kind,
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });

  factory RouteOption.fromJson(Map<String, dynamic> j) => RouteOption(
        kind: (j['kind'] ?? '').toString(),
        points: _pointsFromJson(j['points']),
        distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
        durationMin: (j['duration_min'] as num?)?.toInt() ?? 0,
      );
}

/// Parse a list of [lat, lng] pairs into LatLng, dropping anything out of range.
List<LatLng> _pointsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final out = <LatLng>[];
  for (final p in raw) {
    if (p is List && p.length >= 2) {
      final lat = (p[0] as num?)?.toDouble();
      final lng = (p[1] as num?)?.toDouble();
      if (lat != null &&
          lng != null &&
          lat.abs() <= 90 &&
          lng.abs() <= 180 &&
          !(lat == 0 && lng == 0)) {
        out.add(LatLng(lat, lng));
      }
    }
  }
  return out;
}
