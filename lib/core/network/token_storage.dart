import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'auth.access_token';
  static const _refreshKey = 'auth.refresh_token';

  Future<String?> readAccess() => _read(_accessKey);
  Future<String?> readRefresh() => _read(_refreshKey);

  /// Reads a value, recovering gracefully from corrupt/incompatible secure
  /// storage. On web, `flutter_secure_storage` encrypts with SubtleCrypto and
  /// throws an `OperationError` when stale ciphertext (e.g. from a previous
  /// build or key) can't be decrypted — that must never crash the app or hang
  /// a request, so we wipe and treat it as "no token".
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      await _safeWipe();
      return null;
    }
  }

  Future<void> write({required String access, required String refresh}) async {
    try {
      await _storage.write(key: _accessKey, value: access);
      await _storage.write(key: _refreshKey, value: refresh);
    } catch (_) {
      // Encryption failed against an incompatible key — reset and retry once.
      await _safeWipe();
      try {
        await _storage.write(key: _accessKey, value: access);
        await _storage.write(key: _refreshKey, value: refresh);
      } catch (_) {
        // Persisting the session failed (storage unavailable). The in-memory
        // session still works for this run; reload will require re-login.
      }
    }
  }

  Future<void> clear() async {
    await _safeWipe();
  }

  Future<void> _safeWipe() async {
    try {
      await _storage.deleteAll();
    } catch (_) {
      // best effort
    }
  }
}
