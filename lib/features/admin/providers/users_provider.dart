import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/mock_data.dart';
import '../../../shared/models/user.dart';

class UsersNotifier extends StateNotifier<List<AppUser>> {
  UsersNotifier() : super(List.of(MockData.users));

  void add(AppUser u) {
    state = [...state, u];
  }

  void update(AppUser u) {
    state = [
      for (final x in state) x.username == u.username ? u : x,
    ];
  }

  void remove(String username) {
    state = state.where((u) => u.username != username).toList();
  }
}

final usersProvider =
    StateNotifierProvider<UsersNotifier, List<AppUser>>(
        (ref) => UsersNotifier());
