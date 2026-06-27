import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/lookup_value.dart';
import '../data/lookups_repository.dart';

const lookupCategories = <String>[
  'PAY_TYPE',
  'DELIVERY_TYPE',
  'LR_STATUS',
  'PACKAGE_TYPE',
  'VEHICLE_TYPE',
  'EWB_LOAD_TYPE',
  'ADVANCE_PAID_BY',
  'TRIP_LEAD_BY',
  'VEHICLE_CAPACITY',
];

final lookupsRepositoryProvider = Provider<LookupsRepository>(
  (ref) => LookupsRepository(ref.watch(apiClientProvider)),
);

/// Fetched on login, cached until logout. Returns an empty map when
/// unauthenticated so screens can render without a null check.
final lookupsProvider =
    FutureProvider<Map<String, List<LookupValue>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const {};
  return ref.watch(lookupsRepositoryProvider).fetch(lookupCategories);
});

/// Synchronous accessor to the resolved lookups map (empty until loaded).
/// Convenient for building dropdowns inside widgets.
final lookupsMapProvider = Provider<Map<String, List<LookupValue>>>((ref) {
  return ref.watch(lookupsProvider).valueOrNull ?? const {};
});

/// Returns the values for a single category, sorted by sort order.
List<LookupValue> lookupList(
  Map<String, List<LookupValue>> all,
  String category,
) =>
    all[category] ?? const [];

LookupValue? lookupById(
  Map<String, List<LookupValue>> all,
  String category,
  String? id,
) {
  if (id == null || id.isEmpty) return null;
  for (final v in all[category] ?? const <LookupValue>[]) {
    if (v.id == id) return v;
  }
  return null;
}

LookupValue? lookupByCode(
  Map<String, List<LookupValue>> all,
  String category,
  String code,
) {
  final list = all[category];
  if (list == null) return null;
  for (final v in list) {
    if (v.code == code) return v;
  }
  return null;
}
