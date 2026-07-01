import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/system_config.dart';
import '../data/system_repository.dart';

export '../data/system_config.dart';

final systemRepositoryProvider = Provider<SystemRepository>(
    (ref) => SystemRepository(ref.watch(apiClientProvider)));

class SystemConfigNotifier extends StateNotifier<SystemConfig> {
  SystemConfigNotifier(this._repo, {required bool authed, this.regionId})
      : super(const SystemConfig()) {
    if (authed) refresh();
  }
  final SystemRepository _repo;

  /// The signed-in user's region — selects which numbering row to load/edit
  /// (null for super admins → the tenant-wide fallback row).
  final String? regionId;

  Future<void> refresh() async {
    try {
      state = await _repo.getConfig(regionId: regionId);
    } catch (_) {
      // keep defaults if the config endpoints are unreachable
    }
  }

  /// Local-only update (used for live previews and unpersisted toggles).
  void update(SystemConfig cfg) => state = cfg;

  Future<void> saveNumbering(SystemConfig cfg) async {
    await _repo.saveNumbering(cfg);
    state = cfg;
  }

  Future<void> saveFormat(SystemConfig cfg) async {
    await _repo.saveFormat(cfg);
    state = cfg;
  }
}

final systemConfigProvider =
    StateNotifierProvider<SystemConfigNotifier, SystemConfig>((ref) {
  final user = ref.watch(currentUserProvider);
  return SystemConfigNotifier(
    ref.watch(systemRepositoryProvider),
    authed: user != null,
    regionId: user?.regionId,
  );
});
