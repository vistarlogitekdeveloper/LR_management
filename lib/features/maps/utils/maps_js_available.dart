/// Is the Google Maps JavaScript SDK present in this page?
///
/// Conditional export, guarded on `dart.library.js_interop` rather than
/// `dart.library.html`: the SDK marks `dart:html` unavailable on every wasm
/// target while js_interop stays available, so an html guard silently selects
/// the stub under `--wasm`. Same reasoning as core/utils/file_opener.dart.
///
/// The stub answers false, which is correct for every non-web platform: mobile
/// has no Maps script and no browser key, and draws OSM instead.
library;

export 'maps_js_available_stub.dart'
    if (dart.library.js_interop) 'maps_js_available_web.dart';
