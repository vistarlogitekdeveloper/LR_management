import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/pills.dart';
import '../data/trip_history.dart';
import '../providers/tracking_providers.dart';
import 'trip_history_filters.dart';
import 'tracking_common.dart';

/// Finished trips (delivered / cancelled), newest first. Tapping a row opens
/// the same /tracking/lr/:id trail screen the live map uses, which replays the
/// recorded fixes on the map.
class TripHistoryView extends ConsumerWidget {
  const TripHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(tripHistoryProvider);
    return Column(
      children: [
        const TripHistoryFilters(),
        Expanded(
          // `when` (not a `switch`) so a background reload keeps the current
          // rows on screen instead of flashing the skeleton — Riverpod 2 marks
          // a refresh as AsyncLoading even when it still carries data.
          child: rows.when(
            error: (e, _) => TrackingErrorBox(
              message:
                  'Could not load trip history.\n${friendlyErrorMessage(e)}',
              onRetry: () => ref.invalidate(tripHistorySourceProvider),
            ),
            // Scrollable (never scrolled) so a short viewport clips the
            // skeleton instead of striping it — the cards have a fixed height.
            loading: () => const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ShimmerCards(cards: 6, height: 92),
            ),
            data: (trips) => _TripList(trips: trips),
          ),
        ),
      ],
    );
  }
}

class _TripList extends ConsumerWidget {
  final List<LorryReceipt> trips;
  const _TripList({required this.trips});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trips.isEmpty) {
      final filter = ref.watch(tripHistoryFilterProvider);
      if (filter.isUnfiltered) {
        return const TrackingEmptyState(
          icon: Icons.history_rounded,
          title: 'No finished trips yet',
          message:
              'A trip moves here once its LR is marked Delivered or Cancelled. '
              'Everything still on the road is on the Active trips tab.',
        );
      }
      return TrackingEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No trips match these filters',
        message:
            'Try a different period, or clear the filters to see every '
            'finished trip.',
        actionLabel: 'Clear filters',
        onAction: () => ref.read(tripHistoryFilterProvider.notifier).state =
            const TripHistoryFilter(),
      );
    }

    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scrollbar(
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 24,
          4,
          compact ? 12 : 24,
          16,
        ),
        itemCount: trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _TripTile(lr: trips[i]),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  final LorryReceipt lr;
  const _TripTile({required this.lr});

  @override
  Widget build(BuildContext context) {
    final vehicle = lr.vehicle;
    final who = [
      if (vehicle.number.isNotEmpty) vehicle.number,
      if (lr.tripDriverName.isNotEmpty) lr.tripDriverName,
    ].join(' · ');

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Same destination as a live vehicle: the trail screen renders the
        // recorded fixes whether or not the trip is still running.
        onTap: () => context.go('/tracking/lr/${lr.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TripHeader(number: lr.number, status: lr.status),
              if (who.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate,
                    ),
                  ),
                ),
              if (lr.fromCity.isNotEmpty || lr.toCity.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${lr.fromCity.isEmpty ? '?' : lr.fromCity} → '
                    '${lr.toCity.isEmpty ? '?' : lr.toCity}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.slate,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              _TripFooter(date: lr.date),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripHeader extends StatelessWidget {
  final String number;
  final LrStatus status;
  const _TripHeader({required this.number, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              fontSize: 13.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(status: status),
      ],
    );
  }
}

class _TripFooter extends StatelessWidget {
  final DateTime date;
  const _TripFooter({required this.date});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.event_rounded, size: 13, color: AppColors.slate),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            formatDate(date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
          ),
        ),
        const Text(
          'View trail',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.plum,
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: AppColors.plum,
        ),
      ],
    );
  }
}
