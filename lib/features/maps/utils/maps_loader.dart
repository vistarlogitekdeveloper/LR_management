/// Loads the Google Maps JavaScript SDK on demand, from Dart.
///
/// Why this exists instead of the `<script>` tag every google_maps_flutter_web
/// README shows: that tag made the browser key arrive through TWO independent
/// channels that had to agree — a sed substitution into `web/index.html` and a
/// `--dart-define` — and a build where only one of them landed fell back to
/// OpenStreetMap with no way to tell from the app. It also meant a developer
/// could never see the Google map locally without editing a tracked file and
/// risking a live key in a commit.
///
/// Deferring the load is safe because `GoogleMapsPlugin.registerWith()` only
/// assigns the platform instance; the first thing that actually touches
/// `google.maps` is `gmaps.Map(div, options)`, reached when the `GoogleMap`
/// WIDGET builds. So there is no race to lose as long as the widget is not
/// built until this future resolves — which is exactly what PickerMap does.
///
/// Conditional export guarded on `dart.library.js_interop`, not
/// `dart.library.html`: the SDK marks `dart:html` unavailable on every wasm
/// target while js_interop stays available, so an html guard silently selects
/// the stub under `--wasm`. Same reasoning as core/utils/file_opener.dart.
library;

export 'maps_load_result.dart';
export 'maps_loader_stub.dart'
    if (dart.library.js_interop) 'maps_loader_web.dart';
