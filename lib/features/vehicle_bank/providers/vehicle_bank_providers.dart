import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../data/vehicle_bank_models.dart';
import '../data/vehicle_bank_repository.dart';

final vehicleBankRepositoryProvider = Provider<VehicleBankRepository>(
  (ref) => VehicleBankRepository(ref.watch(apiClientProvider)),
);

/// The filter the screen is currently showing. Update it with
/// `ref.read(vehicleBankFilterProvider.notifier).state = filter.copyWith(...)`
/// — debounce free-text edits (300 ms) before writing, or every keystroke
/// becomes a request.
final vehicleBankFilterProvider = StateProvider<VehicleBankFilter>(
  (ref) => VehicleBankFilter.empty,
);

/// The rows for one filter. Keyed by the filter itself, which is why
/// [VehicleBankFilter] carries value equality — an identical filter reuses the
/// cached fetch instead of re-requesting.
///
/// Refresh with `ref.invalidate(vehicleBankRowsProvider(filter))`, or use
/// [currentVehicleBankRowsProvider] and invalidate with the filter read from
/// [vehicleBankFilterProvider].
final vehicleBankRowsProvider = FutureProvider.autoDispose
    .family<List<VehicleBankRow>, VehicleBankFilter>(
      (ref, filter) => ref.watch(vehicleBankRepositoryProvider).listAll(filter),
    );

/// The rows for the filter currently in [vehicleBankFilterProvider] — what the
/// screen watches so it does not have to thread the family key through its
/// widget tree. Loading and error states come through the AsyncValue unchanged.
final currentVehicleBankRowsProvider =
    Provider.autoDispose<AsyncValue<List<VehicleBankRow>>>((ref) {
      final filter = ref.watch(vehicleBankFilterProvider);
      return ref.watch(vehicleBankRowsProvider(filter));
    });
