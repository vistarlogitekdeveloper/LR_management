import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/mock_data.dart';
import '../../../shared/models/user.dart';

class AuthState {
  final AppUser? user;
  final String? error;
  final bool loading;

  const AuthState({this.user, this.error, this.loading = false});

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    AppUser? user,
    String? error,
    bool? loading,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
      loading: loading ?? this.loading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  Future<bool> login(String username, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    await Future.delayed(const Duration(milliseconds: 350));
    final match = MockData.users.where(
      (u) =>
          u.username.toLowerCase() == username.trim().toLowerCase() &&
          u.password == password,
    );
    if (match.isEmpty) {
      state = state.copyWith(
        loading: false,
        error: 'Invalid username or password',
      );
      return false;
    }
    state = AuthState(user: match.first);
    return true;
  }

  void logout() {
    state = const AuthState();
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());

final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authProvider).user,
);
