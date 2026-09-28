import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/lr_models.dart';
import '../../lr/providers/lr_providers.dart';
import '../data/tracking_repository.dart';
import '../data/trip_history.dart';

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingRepository(ref.watch(apiClientProvider)),
);

/// All actively-tracked vehicles (fleet view). Refresh with
/// `ref.invalidate(activeVehiclesProvider)`.
final activeVehiclesProvider = FutureProvider.autoDispose<List<FleetVehicle>>(
  (ref) => ref.watch(trackingRepositoryProvider).activeVehicles(),
);

/// Trail + consent for one LR.
final lrTrackingProvider = FutureProvider.autoDispose
    .family<LrTracking, String>(
      (ref, lrId) => ref.watch(trackingRepositoryProvider).lrTracking(lrId),
    );

/// Which panel the Live Tracking screen is showing.
///
/// Deliberately NOT autoDispose: opening a past trip from History and coming
/// back should land on History again, not silently reset to Active.
final trackingTabProvider = StateProvider<TrackingTab>(
  (ref) => TrackingTab.active,
);

/// Search / period / status narrowing for the History tab. Kept alive with the
/// tab selection for the same reason.
final tripHistoryFilterProvider = StateProvider<TripHistoryFilter>(
  (ref) => const TripHistoryFilter(),
);

/// Rows the History tab draws from.
///
/// There is no server-side trip-history endpoint — `/tracking/active` returns
/// running trips only — so history is the finished end of the LR list. This
/// reuses the shared LR cache when it is warm (History is another view of the
/// same rows; a second walk of `/lrs` would be pure waste) and otherwise awaits
/// the notifier's own de-duplicated fetch, converting a failure into an error
/// state because nothing is cached to fall back on.
final tripHistorySourceProvider =
    FutureProvider.autoDispose<List<LorryReceipt>>((ref) async {
      final cached = ref.watch(lrListProvider);
      if (cached.isNotEmpty) return cached;

      final notifier = ref.watch(lrListProvider.notifier);
      await notifier.refresh();
      final error = notifier.lastError;
      if (error != null) throw error;
      // A successful load lands as a state change, which recomputes this
      // provider and returns through the cached branch above. Reaching here
      // means the account genuinely has no LRs yet.
      return const <LorryReceipt>[];
    });

/// Finished trips, filtered and newest first — what the History list renders.
final tripHistoryProvider =
    Provider.autoDispose<AsyncValue<List<LorryReceipt>>>((ref) {
      final source = ref.watch(tripHistorySourceProvider);
      final filter = ref.watch(tripHistoryFilterProvider);
      // Anything still on the Active tab is excluded so no LR appears twice.
      final activeIds =
          ref
              .watch(activeVehiclesProvider)
              .valueOrNull
              ?.map((v) => v.lrId)
              .toSet() ??
          const <String>{};
      return source.whenData(
        (all) =>
            filterTripHistory(all, filter: filter, excludeLrIds: activeIds),
      );
    });
