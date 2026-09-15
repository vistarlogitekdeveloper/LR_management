import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/maps/data/maps_repository.dart';

/// The picker used to render four different server outcomes identically,
/// because it only ever saw a list of rows: the geocoder answered, the geocoder
/// found nothing, the primary provider died and the free fallback answered, or
/// the caller never reached the primary at all. A dispatcher typing a real
/// company name saw the same nothing in every case.
///
/// [MapsSearchResult] is what makes those distinguishable, so these tests pin
/// the distinctions rather than the plumbing.
void main() {
  const rows = [
    MapsSuggestion(
      placeId: 'ChIJ1',
      text: 'Vistar Logitek Pvt Ltd, Waluj',
      lat: null,
      lng: null,
      source: 'google',
    ),
  ];

  group('MapsSearchResult', () {
    test('a healthy search is not degraded', () {
      const r = MapsSearchResult(
        suggestions: rows,
        live: 'ok',
        provider: 'google',
      );
      expect(r.degraded, isFalse);
      expect(r.isEmpty, isFalse);
    });

    test('a fallback-served search is degraded even though it has rows', () {
      // This is the case that hid a dead Places integration for days: rows came
      // back, so everything looked fine, but they came from the free provider
      // which does not index business listings.
      const r = MapsSearchResult(
        suggestions: rows,
        live: 'degraded',
        provider: 'nominatim',
      );
      expect(r.degraded, isTrue);
      expect(r.isEmpty, isFalse);
    });

    test('a failed search is degraded and empty, not merely empty', () {
      const r = MapsSearchResult(suggestions: [], live: 'failed');
      expect(r.degraded, isTrue);
      expect(r.isEmpty, isTrue);
    });

    test('a genuinely empty result is NOT reported as degraded', () {
      // "No such place" must stay distinguishable from "the search broke" —
      // collapsing them is the whole bug.
      const r = MapsSearchResult(
        suggestions: [],
        live: 'ok',
        provider: 'google',
      );
      expect(r.degraded, isFalse);
      expect(r.isEmpty, isTrue);
    });

    test(
      'an older server that sends no `live` field is trusted, not blamed',
      () {
        // A build talking to a backend deployed before this field existed must
        // not accuse it of being degraded on every single search.
        const r = MapsSearchResult(suggestions: rows);
        expect(r.live, 'ok');
        expect(r.degraded, isFalse);
        expect(r.provider, isEmpty);
      },
    );
  });
}
