import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/maps/utils/maps_config.dart';
import 'package:lr_management/features/maps/utils/maps_loader.dart';

/// Guards the property that makes the Google map safe to add at all: it is OFF
/// unless a build deliberately turns it on.
///
/// A Google map needs a browser key compiled in AND the SDK to actually load,
/// and if either is misread the failure is silent and ugly: a blank grey
/// rectangle where the picker used to be, with the reason only in the browser
/// console. Defaulting to OpenStreetMap is what keeps a missing or refused key a
/// cosmetic difference rather than a broken screen.
///
/// A plain `flutter test` passes no --dart-define and does not run on web, so
/// this is exactly the "nobody configured anything" case.
void main() {
  group('MapsConfig', () {
    test('no key is compiled in unless the build supplies one', () {
      // If this ever fails, someone has hardcoded a key into the source. The
      // key belongs in the Cloudflare Pages BUILD environment, passed through
      // as --dart-define by cloudflare-build.sh — see the comment on MapsConfig.
      expect(MapsConfig.browserKey, isEmpty);
    });

    test('a Google map is not even attempted by default', () {
      // Also covers every mobile build: the key is a BROWSER key restricted to
      // the web origins, and Android/iOS would need their own platform keys
      // wired into the native projects. Until those exist, mobile must keep the
      // OSM map that works today rather than render an unauthenticated blank.
      expect(MapsConfig.googleMapsRequested, isFalse);
    });
  });

  group('maps loader (non-web stub)', () {
    test('reports unsupported rather than pretending to load', () async {
      expect(await loadGoogleMaps('any-key'), MapsLoadResult.unsupported);
    });

    test('never claims the key was refused off the web', () {
      expect(googleMapsKeyRefused, isFalse);
    });
  });

  group('mapsFallbackMessage', () {
    test('stays silent for the configurations that are not a problem', () {
      // A Google map that drew has nothing to explain, and mobile draws OSM by
      // design — neither should nag on every open.
      expect(mapsFallbackMessage(MapsLoadResult.loaded), isEmpty);
      expect(mapsFallbackMessage(MapsLoadResult.unsupported), isEmpty);
    });

    test('a keyless web build names the missing --dart-define, in debug', () {
      // noKey can ONLY arise in a web build (the non-web loader answers
      // unsupported), so it always means the build was compiled without the
      // define. Leaving it silent made a mistyped run command look exactly like
      // a working OSM fallback, which cost a debugging session.
      // `flutter test` runs in debug, which is the branch that must speak.
      expect(
        mapsFallbackMessage(MapsLoadResult.noKey),
        contains('dart-define'),
      );
    });

    test('explains the two failures a user could otherwise not diagnose', () {
      // These are the cases that used to show a grey box or a silent downgrade.
      expect(mapsFallbackMessage(MapsLoadResult.failed), isNotEmpty);
      expect(mapsFallbackMessage(MapsLoadResult.refused), contains('referrer'));
    });

    test('reassures that the captured pin is still exact', () {
      // The whole point of the picker is the coordinate, not the basemap.
      for (final r in [MapsLoadResult.failed, MapsLoadResult.refused]) {
        expect(mapsFallbackMessage(r), contains('still exact'));
      }
    });
  });
}
