import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the auth tokens so the user stays signed in across refreshes and
/// app restarts.
///
/// Storage backend by platform:
///   - **web**: `shared_preferences` (browser localStorage). `flutter_secure_
///     storage` on web encrypts with SubtleCrypto and frequently fails to
///     decrypt across reloads, which silently logged the user out on every
///     refresh — localStorage persists reliably.
///   - **native (Android/iOS/desktop)**: `flutter_secure_storage`
///     (Keystore/Keychain) so the refresh token is encrypted at rest.
class TokenStorage {
  TokenStorage(this._secure);

  final FlutterSecureStorage _secure;

  static const _accessKey = 'auth.access_token';
  static const _refreshKey = 'auth.refresh_token';

  Future<String?> readAccess() => _read(_accessKey);
  Future<String?> readRefresh() => _read(_refreshKey);

  Future<String?> _read(String key) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key);
      }
      return await _secure.read(key: key);
    } catch (_) {
      // A transient read failure must never crash the app or hang a request —
      // treat it as "no token". We deliberately do NOT wipe here, so a one-off
      // glitch can't sign the user out.
      return null;
    }
  }

  Future<void> write({required String access, required String refresh}) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_accessKey, access);
        await prefs.setString(_refreshKey, refresh);
        return;
      }
      await _secure.write(key: _accessKey, value: access);
      await _secure.write(key: _refreshKey, value: refresh);
    } catch (_) {
      // Persisting failed (storage unavailable). The in-memory session still
      // works for this run; a reload will then require re-login.
    }
  }

  Future<void> clear() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_accessKey);
        await prefs.remove(_refreshKey);
        return;
      }
      await _secure.deleteAll();
    } catch (_) {
      // best effort
    }
  }
}
