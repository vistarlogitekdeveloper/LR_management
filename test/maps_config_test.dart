import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/maps/utils/maps_config.dart';

/// Guards the property that makes the Google map safe to add at all: it is OFF
/// unless a build deliberately turns it on.
///
/// Three independent things have to line up for a Google map to be drawn — web
/// platform, a browser key compiled in, and the Maps script actually present —
/// and if any of them is misread the failure is silent and ugly: a blank grey
/// rectangle where the picker used to be, with the reason only in the browser
/// console. Defaulting to OpenStreetMap is what keeps a missing or refused key
/// a cosmetic difference rather than a broken screen.
///
/// A plain `flutter test` passes no --dart-define and does not run on web, so
/// this is exactly the "nobody configured anything" case.
void main() {
  group('MapsConfig', () {
    test('no key is compiled in unless the build supplies one', () {
      // If this ever fails, someone has hardcoded a key into the source. The
      // key belongs in the Cloudflare Pages environment, injected by
      // cloudflare-build.sh — see the comment on MapsConfig.
      expect(MapsConfig.browserKey, isEmpty);
    });

    test('the picker falls back to OpenStreetMap by default', () {
      // Also covers every mobile build: the key is a BROWSER key restricted to
      // the web domains, and Android/iOS would need their own platform keys
      // wired into the native projects. Until those exist, mobile must keep the
      // OSM map that works today rather than render an unauthenticated blank.
      expect(MapsConfig.googleMapsEnabled, isFalse);
    });
  });
}
