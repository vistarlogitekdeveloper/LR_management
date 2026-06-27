import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../data/capacity_options_repository.dart';

final capacityOptionsRepositoryProvider = Provider<CapacityOptionsRepository>(
  (ref) => CapacityOptionsRepository(ref.watch(apiClientProvider)),
);

class CapacityOptionsNotifier extends StateNotifier<List<CapacityOption>> {
  CapacityOptionsNotifier(this._repo) : super(const []) {
    refresh();
  }
  final CapacityOptionsRepository _repo;

  Future<void> refresh() async {
    try {
      state = await _repo.list();
    } catch (_) {
      // Keep prior state on a transient error; the screen surfaces failures
      // from the explicit add/rename/remove calls.
    }
  }

  Future<void> add(String label) async {
    await _repo.create(label);
    await refresh();
  }

  Future<void> rename(String id, String label) async {
    await _repo.update(id, label);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    await refresh();
  }
}

final capacityOptionsProvider =
    StateNotifierProvider<CapacityOptionsNotifier, List<CapacityOption>>(
      (ref) => CapacityOptionsNotifier(ref.watch(capacityOptionsRepositoryProvider)),
    );
