import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/user.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
    (ref) => AdminRepository(ref.watch(apiClientProvider)));

final rolesProvider = FutureProvider.autoDispose<List<RoleInfo>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(adminRepositoryProvider).listRoles();
});

class UsersNotifier extends StateNotifier<List<AppUser>> {
  UsersNotifier(this._repo, {required bool authed}) : super(const []) {
    if (authed) refresh();
  }
  final AdminRepository _repo;

  Future<void> refresh() async {
    state = await _repo.listUsers();
  }

  Future<void> create({
    required String username,
    required String name,
    required String roleId,
    required String password,
    String? email,
    String? mobile,
    String? regionId,
    bool active = true,
  }) async {
    final created = await _repo.createUser(
      username: username,
      name: name,
      roleId: roleId,
      password: password,
      email: email,
      mobile: mobile,
      regionId: regionId,
      active: active,
    );
    state = [...state, created];
  }

  Future<void> updateUser(
    AppUser existing, {
    String? name,
    String? roleId,
    String? email,
    String? mobile,
    String? regionId,
    bool? active,
  }) async {
    final updated = await _repo.updateUser(
      existing.id,
      existing.version,
      name: name,
      roleId: roleId,
      email: email,
      mobile: mobile,
      regionId: regionId,
      active: active,
    );
    state = [for (final u in state) u.id == updated.id ? updated : u];
  }

  Future<void> remove(String id) async {
    await _repo.deleteUser(id);
    state = state.where((u) => u.id != id).toList();
  }
}

final usersProvider =
    StateNotifierProvider<UsersNotifier, List<AppUser>>((ref) {
  final authed = ref.watch(currentUserProvider) != null;
  return UsersNotifier(ref.watch(adminRepositoryProvider), authed: authed);
});

class RegionsNotifier extends StateNotifier<List<RegionInfo>> {
  RegionsNotifier(this._repo, {required bool authed}) : super(const []) {
    if (authed) refresh();
  }
  final AdminRepository _repo;

  Future<void> refresh() async {
    state = await _repo.listRegions();
  }

  Future<void> add({required String name, String? code}) async {
    final created = await _repo.createRegion(name: name, code: code);
    state = [...state, created];
  }

  Future<void> update(RegionInfo existing,
      {String? name, String? code, bool? active}) async {
    final updated = await _repo.updateRegion(
      existing.id,
      existing.version,
      name: name,
      code: code,
      active: active,
    );
    state = [for (final r in state) r.id == updated.id ? updated : r];
  }

  Future<void> remove(String id) async {
    await _repo.deleteRegion(id);
    state = state.where((r) => r.id != id).toList();
  }
}

/// Region list. Available to any admin (for labels / pickers); only super
/// admins can mutate it (enforced by the backend).
final regionsProvider =
    StateNotifierProvider<RegionsNotifier, List<RegionInfo>>((ref) {
  final authed = ref.watch(currentUserProvider) != null;
  return RegionsNotifier(ref.watch(adminRepositoryProvider), authed: authed);
});
