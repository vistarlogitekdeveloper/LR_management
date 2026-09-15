import 'package:flutter/foundation.dart' show kDebugMode;

/// Outcome of trying to make the Google Maps JavaScript SDK available.
///
/// Every value except [loaded] means the picker draws OpenStreetMap instead.
/// They are kept distinct rather than collapsed to a bool because the user is
/// owed a different sentence for each: "nobody configured a key" is a deploy
/// task, "Google refused the key" is a console task, and "the script never
/// arrived" is usually a blocked network. Collapsing them is what produced the
/// original symptom — a silent fallback nobody could explain.
enum MapsLoadResult {
  /// `google.maps` is present and a map can be built.
  loaded,

  /// No browser key was compiled into this build, so nothing was attempted.
  noKey,

  /// Not a web build. Android and iOS need their own platform keys compiled
  /// into the native projects; until those exist, mobile draws OSM.
  unsupported,

  /// The script tag errored or never finished — network blocked, offline, or
  /// the request timed out.
  failed,

  /// The SDK loaded but Google rejected the key (`gm_authFailure`): the HTTP
  /// referrer restriction does not cover this origin, the Maps JavaScript API
  /// is not enabled on the key, or billing is off. The commonest real-world
  /// cause, and the one that used to render a blank grey rectangle.
  refused,
}

/// The one-line explanation shown under the search box when the picker could
/// not draw a Google map. Empty where nothing is wrong — a plain OSM build
/// should not nag an end user on every open.
///
/// [noKey] is the exception, and only in debug. It can ONLY happen in a web
/// build (the non-web loader answers [unsupported]), so it always means the
/// build was compiled without `--dart-define=GOOGLE_MAPS_BROWSER_KEY`. Staying
/// silent there is what made a mistyped run command indistinguishable from a
/// working OSM fallback — the exact confusion this enum exists to end. Release
/// builds still say nothing, because an operator cannot act on it.
String mapsFallbackMessage(MapsLoadResult result) => switch (result) {
  MapsLoadResult.loaded => '',
  MapsLoadResult.noKey =>
    kDebugMode
        ? 'No Maps browser key in this build — showing OpenStreetMap. Run with '
              '--dart-define=GOOGLE_MAPS_BROWSER_KEY=… to get the Google map.'
        : '',
  MapsLoadResult.unsupported => '',
  MapsLoadResult.failed =>
    "Google Maps didn't load — showing OpenStreetMap. The pin you place is "
        'still exact.',
  MapsLoadResult.refused =>
    'Google refused this key for this address — showing OpenStreetMap. Check '
        "the key's HTTP referrer restrictions. The pin you place is still exact.",
};
