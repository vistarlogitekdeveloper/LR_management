import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/lr_template.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/templates_repository.dart';

final templatesRepositoryProvider = Provider<TemplatesRepository>(
    (ref) => TemplatesRepository(ref.watch(apiClientProvider)));

class TemplatesNotifier extends StateNotifier<List<LrTemplate>> {
  TemplatesNotifier(this._repo, {required bool authed}) : super(const []) {
    if (authed) refresh();
  }
  final TemplatesRepository _repo;

  Future<void> refresh() async {
    try {
      state = await _repo.list();
    } catch (_) {
      // transient error — keep prior state
    }
  }

  Future<void> create(String title, Map<String, dynamic> payload) async {
    final t = await _repo.create(title, payload);
    state = [t, ...state];
  }

  Future<void> update(String id,
      {String? title, Map<String, dynamic>? payload}) async {
    final u = await _repo.update(id, title: title, payload: payload);
    state = [for (final t in state) t.id == u.id ? u : t];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((t) => t.id != id).toList();
  }
}

final templatesProvider =
    StateNotifierProvider<TemplatesNotifier, List<LrTemplate>>((ref) {
  final authed = ref.watch(currentUserProvider) != null;
  return TemplatesNotifier(ref.watch(templatesRepositoryProvider),
      authed: authed);
});
