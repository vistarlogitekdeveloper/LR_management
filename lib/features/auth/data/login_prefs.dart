import 'package:shared_preferences/shared_preferences.dart';

/// Persists the "Remember me" preference — whether the box was ticked and, if
/// so, the last username — so returning users don't retype it. Backed by
/// `shared_preferences` (browser localStorage on web).
///
/// Only the username is ever stored; the password is never persisted. All
/// access is defensive: a storage failure degrades to "nothing remembered"
/// instead of throwing, so it can never block or crash the login flow.
class LoginPrefs {
  LoginPrefs._();

  static const _rememberKey = 'login.remember_me';
  static const _usernameKey = 'login.username';

  /// The remembered state. [username] is empty when nothing is remembered.
  static Future<({bool remember, String username})> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberKey) ?? false;
      final username = remember ? (prefs.getString(_usernameKey) ?? '') : '';
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, remember);
      if (remember && username.isNotEmpty) {
        await prefs.setString(_usernameKey, username);
      } else {
        await prefs.remove(_usernameKey);
      }
    } catch (_) {
      // Best effort — a persistence failure must never block signing in.
    }
  }
}
