import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/maps/utils/google_maps_link.dart';

/// Ops paste plant-gate locations as Google Maps links instead of place names,
/// because a factory gate is not searchable by name. These tests pin the two
/// things that make that safe: the exact place pin beats the viewport centre,
/// and production's projected-metres garbage (lat ~25,555,074) never gets in.

void main() {
  group('parseGoogleMapsLink', () {
    test('the !3d place pin wins over the @ viewport centre', () {
      const url =
          'https://www.google.com/maps/place/TATA+Motors+Chakan/'
          '@18.6512,73.8200,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0'
          '!8m2!3d18.6489!4d73.8213';

      final link = parseGoogleMapsLink(url);

      expect(link, isNotNull);
      expect(link?.lat, closeTo(18.6489, 1e-9));
      expect(link?.lng, closeTo(73.8213, 1e-9));
      expect(link?.precision, GoogleLinkPrecision.placePin);
    });

    test('@ pair tolerates a zoom suffix, a metres suffix and none', () {
      for (final url in const [
        'https://www.google.com/maps/@18.5204,73.8567,17z',
        'https://www.google.com/maps/@18.5204,73.8567,17.5z',
        'https://www.google.com/maps/@18.5204,73.8567,1234m/data=!3m1',
        'https://www.google.com/maps/@18.5204,73.8567',
      ]) {
        final link = parseGoogleMapsLink(url);
        expect(link?.lat, closeTo(18.5204, 1e-9), reason: url);
        expect(link?.lng, closeTo(73.8567, 1e-9), reason: url);
        expect(link?.precision, GoogleLinkPrecision.mapCentre, reason: url);
      }
    });

    test('coordinates are read from every accepted query parameter', () {
      for (final url in const [
        'https://www.google.com/maps?q=18.5204,73.8567',
        'https://www.google.com/maps?q=18.5204%2C73.8567',
        'https://www.google.com/maps?q=18.5204,+73.8567',
        'https://www.google.com/maps/search/?api=1&query=18.5204%2C73.8567',
        'https://maps.google.com/?ll=18.5204,73.8567&z=17',
        'https://maps.google.com/?sll=18.5204,73.8567',
        'https://maps.google.com/maps?saddr=Pune&daddr=18.5204,73.8567',
        'https://www.google.com/maps/dir/?api=1&destination=18.5204%2C73.8567',
        'https://www.google.com/maps/@?api=1&center=18.5204,73.8567',
      ]) {
        final link = parseGoogleMapsLink(url);
        expect(link?.lat, closeTo(18.5204, 1e-9), reason: url);
        expect(link?.lng, closeTo(73.8567, 1e-9), reason: url);
        expect(link?.precision, GoogleLinkPrecision.query, reason: url);
      }
    });

    test('a label after the pair does not break the query form', () {
      final link = parseGoogleMapsLink(
        'https://www.google.com/maps?q=18.5204,73.8567+(TATA+Gate+2)',
      );

      expect(link?.lat, closeTo(18.5204, 1e-9));
      expect(link?.lng, closeTo(73.8567, 1e-9));
    });

    test('negative latitude and negative longitude survive', () {
      final south = parseGoogleMapsLink(
        'https://www.google.com/maps/@-33.8688,151.2093,17z',
      );
      expect(south?.lat, closeTo(-33.8688, 1e-9));
      expect(south?.lng, closeTo(151.2093, 1e-9));

      final west = parseGoogleMapsLink(
        'https://www.google.com/maps?q=40.7128,-74.0060',
      );
      expect(west?.lat, closeTo(40.7128, 1e-9));
      expect(west?.lng, closeTo(-74.006, 1e-9));
    });

    test('a bare pair copied off the info card is accepted', () {
      for (final text in const [
        '18.5204, 73.8567',
        '18.5204,73.8567',
        '(18.5204, 73.8567)',
      ]) {
        final link = parseGoogleMapsLink(text);
        expect(link?.lat, closeTo(18.5204, 1e-9), reason: text);
        expect(link?.lng, closeTo(73.8567, 1e-9), reason: text);
        expect(link?.precision, GoogleLinkPrecision.query, reason: text);
        expect(looksLikeGoogleMapsLink(text), isTrue, reason: text);
      }
    });

    test('integers without a decimal point are valid coordinates', () {
      final link = parseGoogleMapsLink('https://www.google.com/maps?q=18,73');
      expect(link?.lat, 18);
      expect(link?.lng, 73);
    });

    test('short links carry no coordinates', () {
      for (final url in const [
        'https://maps.app.goo.gl/AbCdEfGhIjK1',
        'https://goo.gl/maps/AbCdEfGhIjK1',
      ]) {
        expect(isShortGoogleMapsLink(url), isTrue, reason: url);
        expect(looksLikeGoogleMapsLink(url), isTrue, reason: url);
        expect(parseGoogleMapsLink(url), isNull, reason: url);
      }
    });

    test('a place-name search is not treated as a link', () {
      expect(looksLikeGoogleMapsLink('TATA - Chakan'), isFalse);
      expect(isShortGoogleMapsLink('TATA - Chakan'), isFalse);
      expect(parseGoogleMapsLink('TATA - Chakan'), isNull);
    });

    test('out-of-range values are rejected', () {
      expect(
        parseGoogleMapsLink('https://www.google.com/maps/@91.0,73.8567,17z'),
        isNull,
      );
      expect(
        parseGoogleMapsLink('https://www.google.com/maps/@18.5204,181.0,17z'),
        isNull,
      );
      // The projected-metres shape already sitting in production routes.
      expect(
        parseGoogleMapsLink(
          'https://www.google.com/maps/place/X/data=!3d25555074!4d8215703',
        ),
        isNull,
      );
      expect(parseGoogleMapsLink('25555074, 8215703'), isNull);
    });

    test('the uninitialised (0, 0) pair is rejected', () {
      expect(
        parseGoogleMapsLink('https://www.google.com/maps/@0,0,17z'),
        isNull,
      );
      expect(parseGoogleMapsLink('0,0'), isNull);
      expect(
        parseGoogleMapsLink('https://www.google.com/maps?q=0.0,0.0'),
        isNull,
      );
    });

    test('a malformed !3d falls through to a valid @ pair', () {
      final outOfRange = parseGoogleMapsLink(
        'https://www.google.com/maps/place/X/@18.5204,73.8567,17z/'
        'data=!3d25555074!4d8215703',
      );
      expect(outOfRange?.lat, closeTo(18.5204, 1e-9));
      expect(outOfRange?.lng, closeTo(73.8567, 1e-9));
      expect(outOfRange?.precision, GoogleLinkPrecision.mapCentre);

      final notANumber = parseGoogleMapsLink(
        'https://www.google.com/maps/place/X/@18.5204,73.8567,17z/'
        'data=!3dabc!4d73.8213',
      );
      expect(notANumber?.precision, GoogleLinkPrecision.mapCentre);
    });

    test('scientific notation is not accepted as a coordinate', () {
      expect(parseGoogleMapsLink('1e5,73.8567'), isNull);
      expect(
        parseGoogleMapsLink('https://www.google.com/maps?q=1e2,73.8567'),
        isNull,
      );
    });

    test('a URL that Uri.parse rejects returns null instead of throwing', () {
      const broken = 'https://maps.google.com:notaport/place/TATA';
      expect(() => Uri.parse(broken), throwsFormatException);
      expect(parseGoogleMapsLink(broken), isNull);
    });

    test('coordinates are still recovered from an unparseable URL', () {
      const broken = 'https://maps.google.com:notaport/?q=18.5204,73.8567';
      final link = parseGoogleMapsLink(broken);
      expect(link?.lat, closeTo(18.5204, 1e-9));
      expect(link?.lng, closeTo(73.8567, 1e-9));
    });

    test('empty and whitespace input is null, not a match', () {
      expect(parseGoogleMapsLink('   '), isNull);
      expect(looksLikeGoogleMapsLink('   '), isFalse);
    });

    // Searching a coordinate in Google Maps yields a URL carrying it in the
    // path alone — no @, no !3d/!4d, no query parameter.
    test('a pair in the /maps/place path is recovered', () {
      final link = parseGoogleMapsLink(
        'https://www.google.com/maps/place/18.5204,73.8567',
      );
      expect(link?.lat, closeTo(18.5204, 1e-9));
      expect(link?.lng, closeTo(73.8567, 1e-9));
    });

    test('a pair in the /maps/search path tolerates the + Google inserts', () {
      final link = parseGoogleMapsLink(
        'https://www.google.com/maps/search/18.5204,+73.8567',
      );
      expect(link?.lat, closeTo(18.5204, 1e-9));
      expect(link?.lng, closeTo(73.8567, 1e-9));
    });

    test('an @ pair still outranks one sitting in the path', () {
      final link = parseGoogleMapsLink(
        'https://www.google.com/maps/place/1.0,2.0/@18.5204,73.8567,17z',
      );
      expect(link?.lat, closeTo(18.5204, 1e-9));
      expect(link?.lng, closeTo(73.8567, 1e-9));
      expect(link?.precision, GoogleLinkPrecision.mapCentre);
    });

    test('an out-of-range path pair is rejected, not clamped', () {
      expect(
        parseGoogleMapsLink(
          'https://www.google.com/maps/place/25555074,8213000',
        ),
        isNull,
      );
    });
  });
}
