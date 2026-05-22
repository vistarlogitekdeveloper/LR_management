import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/mock_data.dart';
import '../../../shared/models/lr_models.dart';

class LrFilter {
  final String query;
  final LrStatus? status;
  final String? route;

  const LrFilter({this.query = '', this.status, this.route});

  LrFilter copyWith({String? query, LrStatus? status, String? route, bool clearStatus = false, bool clearRoute = false}) {
    return LrFilter(
      query: query ?? this.query,
      status: clearStatus ? null : (status ?? this.status),
      route: clearRoute ? null : (route ?? this.route),
    );
  }
}

class LrNotifier extends StateNotifier<List<LorryReceipt>> {
  LrNotifier() : super(MockData.seedLrs());

  void add(LorryReceipt lr) => state = [lr, ...state];

  void update(LorryReceipt updated) {
    state = [
      for (final lr in state)
        if (lr.id == updated.id) updated else lr,
    ];
  }

  void remove(String id) {
    state = state.where((lr) => lr.id != id).toList();
  }

  LorryReceipt? findById(String id) =>
      state.where((lr) => lr.id == id).cast<LorryReceipt?>().firstWhere(
            (e) => true,
            orElse: () => null,
          );
}

final lrListProvider =
    StateNotifierProvider<LrNotifier, List<LorryReceipt>>((ref) => LrNotifier());

final lrFilterProvider =
    StateProvider<LrFilter>((ref) => const LrFilter());

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

final lrByIdProvider = Provider.family<LorryReceipt?, String>((ref, id) {
  final list = ref.watch(lrListProvider);
  for (final lr in list) {
    if (lr.id == id) return lr;
  }
  return null;
});
