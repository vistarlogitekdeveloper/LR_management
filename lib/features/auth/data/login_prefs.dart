import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

// On Flutter Web the data is written directly to `window.localStorage`
// (synchronous, always available — no IndexedDB round-trip races). The
// dart:js_interop code that does this lives in login_prefs_storage_web.dart and
// is pulled in ONLY on web via this conditional import, so non-web targets (the
// Dart VM used by `flutter test`, plus native builds) still compile.
import 'login_prefs_storage.dart'
    if (dart.library.js_interop) 'login_prefs_storage_web.dart' as ls;

/// Persists the "Remember me" preference — whether the box was ticked and, if
/// so, the last username — so returning users don't retype it.
///
/// On Flutter **Web** the data is written directly to `window.localStorage`;
/// on other platforms it falls back to `shared_preferences`.
///
/// Only the username is ever stored; the password is never persisted. All
/// access is defensive: a storage failure degrades to "nothing remembered"
/// instead of throwing, so it can never block or crash the login flow.
class LoginPrefs {
  LoginPrefs._();

  // Web localStorage keys.
  static const _rememberKey = 'vistar.login.remember_me';
  static const _usernameKey = 'vistar.login.username';

  // shared_preferences keys (non-web).
  static const _spRememberKey = 'login.remember_me';
  static const _spUsernameKey = 'login.username';

  /// The remembered state. [username] is empty when nothing is remembered.
  static Future<({bool remember, String username})> load() async {
    try {
      if (kIsWeb) {
        final remember = ls.lsGet(_rememberKey) == 'true';
        final username = remember ? (ls.lsGet(_usernameKey) ?? '') : '';
        return (remember: remember, username: username);
      }
      // Non-web: use shared_preferences (backed by the platform key-value store).
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_spRememberKey) ?? false;
      final username = remember ? (prefs.getString(_spUsernameKey) ?? '') : '';
      return (remember: remember, username: username);
    } catch (_) {
      return (remember: false, username: '');
    }
  }

  /// Saves [username] when [remember] is true; otherwise clears any remembered
  /// username. Never throws.
  static Future<void> save({
    required bool remember,
    required String username,
  }) async {
    try {
      if (kIsWeb) {
        ls.lsSet(_rememberKey, remember ? 'true' : 'false');
        if (remember && username.isNotEmpty) {
          ls.lsSet(_usernameKey, username);
        } else {
          ls.lsRemove(_usernameKey);
        }
        return;
      }
      // Non-web path.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_spRememberKey, remember);
      if (remember && username.isNotEmpty) {
        await prefs.setString(_spUsernameKey, username);
      } else {
        await prefs.remove(_spUsernameKey);
      }
    } catch (_) {
      // Best effort — a persistence failure must never block signing in.
    }
  }
}
