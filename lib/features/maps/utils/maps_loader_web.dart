import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'maps_load_result.dart';

/// Name of the global Google calls once the SDK is ready. `loading=async`
/// requires a callback; without one the SDK logs a performance warning and we
/// would be left polling for `google.maps` to appear.
const String _readyCallback = '__vistarGoogleMapsReady';

/// Google calls a global with THIS exact name when it rejects the key — bad
/// referrer, Maps JavaScript API not enabled, or billing off. It is the only
/// signal for that failure: the script tag itself loads fine with a dead key,
/// and the map then renders a watermarked or blank surface. Hooking it is what
/// turns "the map is grey and nobody knows why" into a sentence on screen.
const String _authFailureHook = 'gm_authFailure';

/// Id on the injected tag so a retry replaces it rather than stacking a second
/// copy of the SDK into the page.
const String _scriptId = '__vistar_gmaps_sdk';

Future<MapsLoadResult>? _inFlight;
bool _refused = false;

/// Never closed, deliberately: it is a library-level broadcast for the lifetime
/// of the app, and there is no later moment at which closing it would be
/// correct. Listeners are per-dialog and cancel their own subscriptions.
final StreamController<void> _authFailures = StreamController<void>.broadcast();

/// True once Google has rejected the key. Sticky for the session — a refused
/// key stays refused, so later opens go straight to OSM instead of flashing a
/// map that is about to fail again.
bool get googleMapsKeyRefused => _refused;

/// Fires when Google rejects the key AFTER the SDK reported itself loaded.
/// A picker already showing a Google map listens to this so it can swap back to
/// OSM rather than sit on a dead surface.
Stream<void> get googleMapsAuthFailures => _authFailures.stream;

/// True when `window.google.maps` exists.
///
/// `has` is used rather than reading `google.maps` directly because reading a
/// property off an undefined global is a ReferenceError, and this runs while a
/// widget is building — a throw here would take the dialog down rather than
/// degrade it. The try/catch is a second belt for the same reason.
bool _sdkPresent() {
  try {
    if (!globalContext.has('google')) return false;
    final google = globalContext.getProperty<JSAny?>('google'.toJS);
    if (google == null) return false;
    final maps = (google as JSObject).getProperty<JSAny?>('maps'.toJS);
    if (maps == null) return false;
    // `google.maps` appears before the library has finished initialising, so
    // the namespace alone is not proof. `Map` is the constructor the plugin
    // actually calls; if it is there, a map can be built.
    return (maps as JSObject).has('Map');
  } catch (_) {
    return false;
  }
}

void _installAuthFailureHook() {
  if (globalContext.has(_authFailureHook)) return;
  globalContext.setProperty(
    _authFailureHook.toJS,
    (() {
      _refused = true;
      if (!_authFailures.isClosed) _authFailures.add(null);
    }).toJS,
  );
}

/// Ensures the Maps JavaScript SDK is available, injecting it if needed.
///
/// Single-flight: concurrent callers share one in-flight load, so opening two
/// pickers quickly cannot request the SDK twice. A FAILED attempt clears the
/// cache so a later open may retry (the usual cause is a transient network),
/// while a REFUSED key does not — that one will not fix itself.
Future<MapsLoadResult> loadGoogleMaps(
  String apiKey, {
  Duration timeout = const Duration(seconds: 12),
}) {
  if (apiKey.isEmpty) return Future<MapsLoadResult>.value(MapsLoadResult.noKey);
  if (_refused) return Future<MapsLoadResult>.value(MapsLoadResult.refused);
  // The in-flight load is consulted BEFORE the fast path. `google.maps` is
  // published partway through initialisation, so a picker reopened during an
  // injection would otherwise take the fast path and report `loaded` against a
  // half-built SDK.
  final inFlight = _inFlight;
  if (inFlight != null) return inFlight;
  if (_sdkPresent()) {
    // Covers a page that still ships a <script> tag of its own.
    _installAuthFailureHook();
    return Future<MapsLoadResult>.value(MapsLoadResult.loaded);
  }
  return _inFlight = _inject(apiKey, timeout);
}

Future<MapsLoadResult> _inject(String apiKey, Duration timeout) async {
  _installAuthFailureHook();
  final completer = Completer<MapsLoadResult>();
  void finish(MapsLoadResult r) {
    if (!completer.isCompleted) completer.complete(r);
  }

  globalContext.setProperty(
    _readyCallback.toJS,
    (() => finish(MapsLoadResult.loaded)).toJS,
  );

  web.document.getElementById(_scriptId)?.remove();

  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..id = _scriptId
    ..async = true
    ..src =
        'https://maps.googleapis.com/maps/api/js'
        '?key=${Uri.encodeQueryComponent(apiKey)}'
        '&loading=async'
        '&callback=$_readyCallback';
  script.addEventListener(
    'error',
    ((web.Event _) => finish(MapsLoadResult.failed)).toJS,
  );
  web.document.head?.appendChild(script);

  // A tab that is throttled or behind a captive portal can leave the request
  // hanging indefinitely; the picker must not sit on a skeleton forever.
  final timer = Timer(timeout, () => finish(MapsLoadResult.failed));
  final result = await completer.future;
  timer.cancel();

  // gm_authFailure can beat this future home when the key is bad.
  if (_refused) {
    _inFlight = null;
    return MapsLoadResult.refused;
  }
  if (result != MapsLoadResult.loaded) _inFlight = null;
  return result;
}
