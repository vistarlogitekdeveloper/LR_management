import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/network/token_storage.dart';
import '../../../shared/models/user.dart';

class AuthState {
  final AppUser? user;
  final String? error;
  final bool loading;

  /// True only while the app is restoring a session on startup/refresh (reading
  /// the stored token and validating it via /auth/me). The router shows a splash
  /// instead of bouncing to /login during this window.
  final bool initializing;

  const AuthState({
    this.user,
    this.error,
    this.loading = false,
    this.initializing = false,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    AppUser? user,
    String? error,
    bool? loading,
    bool? initializing,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
      loading: loading ?? this.loading,
      initializing: initializing ?? this.initializing,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api, this._tokens)
      : super(const AuthState(initializing: true)) {
    _bootstrap();
  }

  final ApiClient _api;
  final TokenStorage _tokens;

  Future<void> _bootstrap() async {
    final access = await _tokens.readAccess();
    if (access == null || access.isEmpty) {
      state = const AuthState(initializing: false);
      return;
    }
    try {
      final res = await _api.dio.get('/auth/me');
      // /auth/me returns { data: { user: {...} } } — parse the NESTED user,
      // exactly like login does. Reading res.data['data'] directly handed
      // AppUser.fromJson the { user: ... } wrapper, so username was null and
      // the non-null cast threw — bouncing every refresh to /login despite a
      // perfectly valid session.
      final data = (res.data['data'] as Map).cast<String, dynamic>();
      final user = AppUser.fromJson(
        (data['user'] as Map).cast<String, dynamic>(),
      );
      state = AuthState(user: user);
    } catch (_) {
      // Do NOT wipe the tokens here. The API client already clears them on a
      // DEFINITIVE auth rejection (a 4xx from /auth/refresh); a transient
      // failure (backend cold-start / offline) leaves them in place so the
      // next launch can restore the session instead of forcing a re-login.
      state = const AuthState(initializing: false);
    }
  }

  Future<bool> login(
    String username,
    String password, {
    String? tenantCode,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _api.dio.post('/auth/login', data: {
        'tenant_code': tenantCode ?? ApiConfig.defaultTenantCode,
        'username': username.trim(),
        'password': password,
      });
      final data = (res.data['data'] as Map).cast<String, dynamic>();
      final access = data['access_token'] as String;
      final refresh = data['refresh_token'] as String;
      await _tokens.write(access: access, refresh: refresh);
      final user = AppUser.fromJson(
        (data['user'] as Map).cast<String, dynamic>(),
      );
      state = AuthState(user: user);
      return true;
    } on DioException catch (e) {
      final err = e.error;
      final msg =
          err is ApiException ? err.message : 'Invalid username or password';
      state = state.copyWith(loading: false, error: msg);
      return false;
    } catch (_) {
      // Never leave the button stuck on a non-network failure.
      state = state.copyWith(
          loading: false, error: 'Login failed. Please try again.');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _api.dio.post('/auth/logout');
    } catch (_) {
      // best-effort; clear local session regardless
    }
    await _tokens.clear();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);

final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authProvider).user,
);
