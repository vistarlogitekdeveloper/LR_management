import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/maps/data/maps_repository.dart';

/// Guards the rule that decides whether a search result can move the map.
///
/// The bug this exists to prevent: Google Places Autocomplete returns matches
/// WITHOUT coordinates — resolving a pin is a second call. The previous client
/// read `(m['lat'] as num?)?.toDouble() ?? 0`, so a missing coordinate became
/// 0.0, and 0,0 is a real point in the Gulf of Guinea. The pin landed there
/// silently, and "Use this" would have saved it as a route endpoint.
///
/// So "has a usable pin" is a decision, not a coercion, and it is made here.
void main() {
  MapsSuggestion make({double? lat, double? lng, String placeId = 'p1'}) =>
      MapsSuggestion(placeId: placeId, text: 'Somewhere', lat: lat, lng: lng);

  group('MapsSuggestion.hasCoords', () {
    test('a real pin is usable', () {
      expect(make(lat: 18.5204, lng: 73.8567).hasCoords, isTrue);
      expect(make(lat: 18.5204, lng: 73.8567).needsResolve, isFalse);
    });

    test('null coordinates need resolving, and are never read as zero', () {
      final s = make(lat: null, lng: null);
      expect(s.hasCoords, isFalse);
      expect(s.needsResolve, isTrue);
      // The point of the nullable type: there is no value here to mistake for
      // a location.
      expect(s.lat, isNull);
      expect(s.lng, isNull);
    });

    test('half a coordinate is not a coordinate', () {
      expect(make(lat: 18.5204, lng: null).hasCoords, isFalse);
      expect(make(lat: null, lng: 73.8567).hasCoords, isFalse);
    });

    test('null island is treated as absent, not as a location', () {
      // This is the exact value the old `?? 0` produced for both fields.
      expect(make(lat: 0, lng: 0).hasCoords, isFalse);
      expect(make(lat: 0, lng: 0).needsResolve, isTrue);
    });

    test('a genuine zero on ONE axis is still a real place', () {
      // The equator and the prime meridian are real. Only the pair is rejected,
      // so a location off the coast of Ghana or in Gabon still works.
      expect(make(lat: 0, lng: 73.8567).hasCoords, isTrue);
      expect(make(lat: 18.5204, lng: 0).hasCoords, isTrue);
    });

    test('out-of-range values are refused', () {
      // Production holds route rows whose lat/lng were written in PROJECTED
      // METRES by an older picker (lat ~25,555,074). Centring on one flies the
      // map off the world.
      expect(make(lat: 25555074, lng: 8534221).hasCoords, isFalse);
      expect(make(lat: 91, lng: 0).hasCoords, isFalse);
      expect(make(lat: 0, lng: 181).hasCoords, isFalse);
    });

    test('source defaults to empty rather than null', () {
      // The picker branches on `source == 'saved_place'` to mark our own
      // verified gates; a null there would need a guard at every use.
      expect(make(lat: 1, lng: 1).source, '');
    });
  });
}
