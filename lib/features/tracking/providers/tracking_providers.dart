import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../data/tracking_repository.dart';

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
