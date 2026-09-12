import 'package:flutter/foundation.dart' show kIsWeb;

import 'maps_js_available.dart';

/// Whether this build draws its picker on a real Google map, and why.
///
/// THE KEY IS NOT A SECRET, but it is also not in the repository. A Maps
/// JavaScript API key is visible in any web bundle that uses it — that is
/// unavoidable, and Google's answer is the HTTP-referrer restriction on the key
/// rather than secrecy. Keeping it out of the source still buys two things:
/// rotating it is a dashboard change rather than a code change, and a fork or a
/// leaked checkout does not hand someone a key that bills to this account.
///
/// It arrives twice, from ONE Cloudflare Pages environment variable
/// (`GOOGLE_MAPS_BROWSER_KEY`), because two different layers need it:
///   - `web/index.html` gets the `<script>` tag, substituted by
///     cloudflare-build.sh. Without that script `google.maps` does not exist and
///     google_maps_flutter_web cannot draw anything.
///   - this file gets `--dart-define`, so Dart can decide which map to build.
/// Both come from the same variable, so they cannot disagree.
class MapsConfig {
  MapsConfig._();

  /// Passed at build time:
  ///   flutter build web --dart-define=GOOGLE_MAPS_BROWSER_KEY=...
  /// Empty in local dev and in any build that did not set it.
  static const String browserKey = String.fromEnvironment(
    'GOOGLE_MAPS_BROWSER_KEY',
  );

  /// True when the picker should draw a Google map instead of OSM tiles.
  ///
  /// Three conditions, and all three have to hold:
  ///
  ///   kIsWeb — the key is a BROWSER key, restricted to the Pages domains. A
  ///     Google map on Android or iOS needs its own platform key wired into
  ///     AndroidManifest.xml / AppDelegate.swift, and without one the map view
  ///     renders blank. Mobile therefore stays on OSM, which works today and
  ///     needs no key at all. This is the line to change when mobile keys exist.
  ///
  ///   a key was built in — nothing to authenticate the tiles otherwise.
  ///
  ///   the Maps script actually loaded — see [googleMapsJsAvailable]. This is
  ///     the one that earns its keep in practice: a referrer restriction that
  ///     does not cover the domain being served (a Cloudflare *preview*
  ///     deployment is the classic miss) leaves `google.maps` undefined, and
  ///     without this check the user gets a blank grey rectangle with the reason
  ///     visible only in the browser console. With it, they get the OSM map they
  ///     had before and the picker keeps working.
  static bool get googleMapsEnabled =>
      kIsWeb && browserKey.isNotEmpty && googleMapsJsAvailable();
}
