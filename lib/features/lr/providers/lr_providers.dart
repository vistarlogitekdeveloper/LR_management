import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/lr_models.dart';
import '../../lookups/providers/lookups_provider.dart';
import '../data/lr_repository.dart';

class LrFilter {
  final String query;
  final LrStatus? status;
  final String? route;

  const LrFilter({this.query = '', this.status, this.route});

  LrFilter copyWith(
      {String? query,
      LrStatus? status,
      String? route,
      bool clearStatus = false,
      bool clearRoute = false}) {
    return LrFilter(
      query: query ?? this.query,
      status: clearStatus ? null : (status ?? this.status),
      route: clearRoute ? null : (route ?? this.route),
    );
  }
}

final lrRepositoryProvider = Provider<LrRepository>((ref) {
  final lookups = ref.watch(lookupsProvider).valueOrNull ?? const {};
  return LrRepository(ref.watch(apiClientProvider), lookups);
});

class LrNotifier extends StateNotifier<List<LorryReceipt>> {
  LrNotifier(this._repo) : super(const []) {
    refresh();
  }
  final LrRepository _repo;

  Future<void> refresh() async {
    try {
      state = await _repo.list();
    } catch (_) {
      // A transient backend/DB error shouldn't crash the UI; keep prior state.
    }
  }

  Future<LorryReceipt> create(Map<String, dynamic> payload,
      {EwbInput? ewb, String? idempotencyKey}) async {
    final created =
        await _repo.create(payload, ewb: ewb, idempotencyKey: idempotencyKey);
    state = [created, ...state];
    return created;
  }

  Future<LorryReceipt> updateLr(
    String id,
    int version,
    Map<String, dynamic> payload, {
    EwbInput? ewb,
    String? existingEwbId,
    int existingEwbVersion = 0,
  }) async {
    final updated = await _repo.update(id, version, payload,
        ewb: ewb,
        existingEwbId: existingEwbId,
        existingEwbVersion: existingEwbVersion);
    state = [for (final lr in state) lr.id == updated.id ? updated : lr];
    return updated;
  }

  /// Marks the 90% transporter advance as paid (backend computes the amount and
  /// triggers the notification email), then refreshes the LR in local state.
  Future<LorryReceipt> markAdvancePaid(String id, int version) async {
    final updated = await _repo.markAdvancePaid(id, version);
    state = [for (final lr in state) lr.id == updated.id ? updated : lr];
    return updated;
  }

  /// Completes the payment (releases the POD balance; backend settles the amount
  /// and triggers the notification email), then refreshes the LR in local state.
  Future<LorryReceipt> completePayment(String id, int version) async {
    final updated = await _repo.completePayment(id, version);
    state = [for (final lr in state) lr.id == updated.id ? updated : lr];
    return updated;
  }

  Future<void> changeStatus(String id, LrStatus to, {String? reason}) async {
    await _repo.changeStatus(id, to.code, reason: reason);
    final fresh = await _repo.getById(id);
    state = [for (final lr in state) lr.id == id ? fresh : lr];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((lr) => lr.id != id).toList();
  }

  LorryReceipt? findById(String id) {
    for (final lr in state) {
      if (lr.id == id) return lr;
    }
    return null;
  }
}

final lrListProvider =
    StateNotifierProvider<LrNotifier, List<LorryReceipt>>((ref) {
  return LrNotifier(ref.watch(lrRepositoryProvider));
});

final lrFilterProvider = StateProvider<LrFilter>((ref) => const LrFilter());

final filteredLrsProvider = Provider<List<LorryReceipt>>((ref) {
  final list = ref.watch(lrListProvider);
  final filter = ref.watch(lrFilterProvider);
  return list.where((lr) {
    if (filter.status != null && lr.status != filter.status) return false;
    if (filter.route != null && lr.route != filter.route) return false;
    if (filter.query.isNotEmpty) {
      final q = filter.query.toLowerCase();
      final hay = [
        lr.number,
        lr.consignor.name,
        lr.consignee.name,
        lr.vehicle.number,
        lr.route,
        lr.ewb?.number ?? '',
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList();
});

/// Quick summary lookup from the already-loaded list.
final lrByIdProvider = Provider.family<LorryReceipt?, String>((ref, id) {
  final list = ref.watch(lrListProvider);
  for (final lr in list) {
    if (lr.id == id) return lr;
  }
  return null;
});

/// Full LR detail (invoice items, attachments, freight, EWB) fetched on demand.
final lrDetailProvider =
    FutureProvider.autoDispose.family<LorryReceipt, String>((ref, id) async {
  return ref.watch(lrRepositoryProvider).getById(id);
});
