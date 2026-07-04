// Non-web stub for the localStorage helpers. On web this file is swapped for
// login_prefs_storage_web.dart via the conditional import in login_prefs.dart.
//
// These are never called off-web — LoginPrefs guards every use behind
// `kIsWeb` and uses shared_preferences on native/VM. The stub exists purely so
// the VM (used by `flutter test`) and native builds compile without importing
// the web-only `dart:js_interop`.
String? lsGet(String key) => null;
void lsSet(String key, String value) {}
void lsRemove(String key) {}
