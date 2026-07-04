import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Direct `window.localStorage` access for Flutter Web — synchronous and
// reliable within a browser session (unlike shared_preferences, which uses
// IndexedDB on web and can silently fail to round-trip data). Selected via the
// conditional import in login_prefs.dart; only ever compiled for the web target.

String? lsGet(String key) {
  try {
    final storage = globalContext.getProperty<JSObject?>('localStorage'.toJS);
    if (storage == null) return null;
    final val = storage.callMethod<JSAny?>('getItem'.toJS, key.toJS);
    // getItem() returns JS null when the key is absent — isA<JSString>()
    // safely distinguishes a real string from JS null/undefined.
    if (val == null || !val.isA<JSString>()) return null;
    return (val as JSString).toDart;
  } catch (_) {
    return null;
  }
}

void lsSet(String key, String value) {
  try {
    final storage = globalContext.getProperty<JSObject?>('localStorage'.toJS);
    storage?.callMethod<JSAny?>('setItem'.toJS, key.toJS, value.toJS);
  } catch (_) {}
}

void lsRemove(String key) {
  try {
    final storage = globalContext.getProperty<JSObject?>('localStorage'.toJS);
    storage?.callMethod<JSAny?>('removeItem'.toJS, key.toJS);
  } catch (_) {}
}
