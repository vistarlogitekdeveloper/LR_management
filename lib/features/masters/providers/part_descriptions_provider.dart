import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/part_description.dart';
import '../data/part_descriptions_repository.dart';

final partDescriptionsRepositoryProvider = Provider<PartDescriptionsRepository>(
  (ref) => PartDescriptionsRepository(ref.watch(apiClientProvider)),
);

final partDescriptionsProvider =
    StateNotifierProvider<PartDescriptionsNotifier, List<PartDescription>>(
  (ref) => PartDescriptionsNotifier(ref.watch(partDescriptionsRepositoryProvider)),
);

class PartDescriptionsNotifier extends StateNotifier<List<PartDescription>> {
  PartDescriptionsNotifier(this._repo) : super(const []) {
    refresh();
  }
  final PartDescriptionsRepository _repo;

  Future<void> refresh() async {
    try {
      state = await _repo.list();
    } catch (_) {
      // A transient backend/DB error shouldn't crash the UI; keep prior state.
    }
  }

  Future<void> add(PartDescription p) async {
    final created = await _repo.create(p);
    state = [...state, created];
  }

  Future<void> update(PartDescription p) async {
    final updated = await _repo.update(p);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}
