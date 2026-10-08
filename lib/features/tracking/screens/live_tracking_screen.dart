import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../lr/providers/lr_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/fleet_filter.dart';
import '../data/trip_history.dart';
import '../providers/tracking_providers.dart';
import '../widgets/fleet_filters.dart';
import '../widgets/fleet_view.dart';
import '../widgets/tracking_common.dart';
import '../widgets/tracking_tabs.dart';
import '../widgets/trip_history_view.dart';

/// Tracking home: a live fleet map of everything on the road, and a searchable
/// history of finished trips. Both tabs open the same per-LR trail screen at
/// /tracking/lr/:id.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  Timer? _auto;

  /// History is built lazily and then kept mounted, so the map keeps its camera
  /// and the history list its scroll position when the user switches back and
  /// forth. Without this the IndexedStack would load the LR list on first paint
  /// even for users who never open the tab.
  bool _historyMounted = false;

  /// In-flight flag for the Refresh button, so a tap gives feedback immediately
  /// and can't be double-fired.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Light auto-refresh so the fleet map stays current without user action.
    // History is a static record, so it is left alone.
    _auto = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      if (ref.read(trackingTabProvider) == TrackingTab.active) {
        ref.invalidate(activeVehiclesProvider);
      }
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  Future<void> _refresh(TrackingTab tab) async {
    if (tab == TrackingTab.active) {
      ref.invalidate(activeVehiclesProvider);
      return;
    }
    // History reads the shared LR cache, which serves anything loaded in the
    // last 30 s without a round trip — an explicit Refresh has to bypass that.
    setState(() => _refreshing = true);
    try {
      await ref.read(lrListProvider.notifier).refresh(force: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _selectTab(TrackingTab tab) {
    if (tab == TrackingTab.history && !_historyMounted) {
      setState(() => _historyMounted = true);
    }
    ref.read(trackingTabProvider.notifier).state = tab;
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(trackingTabProvider);
    final active = ref.watch(activeVehiclesProvider);
    final historyCount = _historyMounted
        ? ref.watch(tripHistoryProvider).valueOrNull?.length
        : null;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Live Tracking',
            subtitle: tab.subtitle,
            // The tab switch rides in the header row rather than a band of its
            // own, so the map keeps that vertical space. AppTopbar stacks its
            // actions under the title below 900 px, so both still fit there.
            actions: [
              TrackingTabs(
                selected: tab,
                onChanged: _selectTab,
                // Live trips only — a month-old trip nobody closed is not
                // "active".
                activeCount: active.whenOrNull(
                  data: (v) => fleetScopeCounts(v, null)[FleetScope.live],
                ),
                historyCount: historyCount,
              ),
              AppButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                kind: BtnKind.ghost,
                small: true,
                loading: _refreshing,
                onPressed: _refreshing ? null : () => _refresh(tab),
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: tab.index,
              sizing: StackFit.expand,
              children: [
                const _ActivePanel(),
                if (_historyMounted)
                  const TripHistoryView()
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivePanel extends ConsumerWidget {
  const _ActivePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(activeVehiclesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => TrackingErrorBox(
            message: 'Could not load tracking.\n${friendlyErrorMessage(e)}',
            onRetry: () => ref.invalidate(activeVehiclesProvider),
          ),
          data: (vehicles) {
            final filter = ref.watch(fleetFilterProvider);
            final shown = filterFleet(vehicles, filter);
            return Column(
              children: [
                FleetFilters(all: vehicles),
                Expanded(
                  // Keyed on scope + region so the map re-fits to what is now
                  // shown; the 60 s refresh and typing keep the camera.
                  child: FleetView(
                    key: ValueKey('${filter.scope}|${filter.region}'),
                    vehicles: shown,
                    empty: _emptyFor(ref, filter),
                  ),
                ),
              ],
            );
          },
        );
  }

  Widget _emptyFor(WidgetRef ref, FleetFilter filter) {
    void reset() =>
        ref.read(fleetFilterProvider.notifier).state = const FleetFilter();
    if (filter.query.trim().isNotEmpty || filter.region != null) {
      return TrackingEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching trips',
        message: 'Nothing in "${filter.scope.label}" matches this search.',
        actionLabel: 'Clear filters',
        onAction: reset,
      );
    }
    return switch (filter.scope) {
      FleetScope.live => const TrackingEmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No vehicles on the road',
        message:
            'Only trips with a location in the last 24 h (or started today) '
            'show here. Older ones are under "No signal 24h+"; finished trips '
            'are on the History tab.',
      ),
      FleetScope.noSignal => const TrackingEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing stale',
        message: 'Every running trip has reported in the last 24 h.',
      ),
      FleetScope.consentPending => const TrackingEmptyState(
        icon: Icons.verified_user_outlined,
        title: 'No consent pending',
        message: 'Every running trip\'s driver has answered the SIM consent.',
      ),
      FleetScope.all => const TrackingEmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No trips running',
        message:
            'Tracking starts when an LR is created for a driver whose SIM '
            'consent is approved. Finished trips are on the History tab.',
      ),
    };
  }
}
