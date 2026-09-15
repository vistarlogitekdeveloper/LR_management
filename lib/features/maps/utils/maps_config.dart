import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether this build should try to draw its picker on a real Google map.
///
/// THE KEY IS NOT A SECRET, but it is also not in the repository. A Maps
/// JavaScript API key is visible in any web bundle that uses it — that is
/// unavoidable, and Google's answer is the HTTP-referrer restriction on the key
/// rather than secrecy. Keeping it out of the source still buys two things:
/// rotating it is a dashboard change rather than a code change, and a fork or a
/// leaked checkout does not hand someone a key that bills to this account.
///
/// It arrives through exactly ONE channel: `--dart-define`. It used to arrive
/// through two — a sed substitution into `web/index.html` as well — and the two
/// could disagree, which is precisely how a deploy ended up silently drawing
/// OpenStreetMap. The SDK is now injected at runtime by
/// features/maps/utils/maps_loader.dart, so the define is the only input and
/// there is nothing left to keep in sync.
class MapsConfig {
  MapsConfig._();

  /// Passed at build time:
  ///   flutter run   --dart-define=GOOGLE_MAPS_BROWSER_KEY=...
  ///   flutter build --dart-define=GOOGLE_MAPS_BROWSER_KEY=...
  /// Empty in any build that did not set it, which is a supported
  /// configuration: the picker draws OpenStreetMap and still returns an exact
  /// pin.
  static const String browserKey = String.fromEnvironment(
    'GOOGLE_MAPS_BROWSER_KEY',
  );

  /// True when the picker should ATTEMPT a Google map. Whether it gets one is
  /// decided later and asynchronously by the loader — the script can still be
  /// blocked, time out, or be refused for this origin — so this is deliberately
  /// named for the intent rather than the outcome.
  ///
  /// [kIsWeb] because the key is a BROWSER key, restricted to the web origins.
  /// A Google map on Android or iOS needs its own platform key wired into
  /// AndroidManifest.xml / AppDelegate.swift, and without one the map view
  /// renders blank. Mobile therefore stays on OSM, which works today and needs
  /// no key at all. This is the line to change when mobile keys exist.
  static bool get googleMapsRequested => kIsWeb && browserKey.isNotEmpty;
}
