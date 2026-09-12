import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// True when `window.google.maps` exists — i.e. the script tag in
/// `web/index.html` loaded and was accepted.
///
/// It can legitimately be false in a build that HAS a key: the commonest cause
/// is an HTTP-referrer restriction that does not list the domain being served,
/// and a Cloudflare Pages *preview* deployment (`<hash>.lr-management.pages.dev`)
/// is the one people forget. Google then refuses the script and `google.maps`
/// never appears. Checking costs one property read and turns a blank grey
/// rectangle into the OSM map the picker used before.
///
/// `has` is used rather than reading `google.maps` directly because reading a
/// property off an undefined global is a ReferenceError, and this runs during
/// the first build of the picker — a throw here would take the dialog down
/// rather than degrade it. The try/catch is a second belt for the same reason.
bool googleMapsJsAvailable() {
  try {
    if (!globalContext.has('google')) return false;
    final google = globalContext.getProperty<JSAny?>('google'.toJS);
    if (google == null) return false;
    return (google as JSObject).has('maps');
  } catch (_) {
    return false;
  }
}
