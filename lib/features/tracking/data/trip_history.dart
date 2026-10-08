import '../../../shared/models/lr_models.dart';

/// Which panel the Live Tracking screen is showing.
enum TrackingTab { active, history }

extension TrackingTabX on TrackingTab {
  String get label => switch (this) {
    TrackingTab.active => 'Active trips',
    TrackingTab.history => 'History',
  };

  /// Header subtitle, so the page says what is on screen right now.
  String get subtitle => switch (this) {
    TrackingTab.active => 'All active vehicles',
    TrackingTab.history => 'Completed and cancelled trips',
  };
}

/// Rolling window the history list is limited to. Anchored on "now" rather than
/// a fixed date so the choice keeps meaning the same thing tomorrow.
enum TripPeriod { days30, days90, year, all }

extension TripPeriodX on TripPeriod {
  String get label => switch (this) {
    TripPeriod.days30 => 'Last 30 days',
    TripPeriod.days90 => 'Last 90 days',
    TripPeriod.year => 'Last 12 months',
    TripPeriod.all => 'All time',
  };

  /// Inclusive lower bound (calendar day) for the LR date, or null for all time.
  DateTime? cutoff(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      TripPeriod.days30 => today.subtract(const Duration(days: 30)),
      TripPeriod.days90 => today.subtract(const Duration(days: 90)),
      TripPeriod.year => DateTime(today.year - 1, today.month, today.day),
      TripPeriod.all => null,
    };
  }
}

/// Filters applied to the trip-history list. All of them narrow an in-memory
/// list, so changing one is instant — no request is made.
class TripHistoryFilter {
  final String query;
  final TripPeriod period;

  /// null = both finished states (delivered + cancelled).
  final LrStatus? status;

  const TripHistoryFilter({
    this.query = '',
    this.period = TripPeriod.all,
    this.status,
  });

  /// True while the list is showing everything it can — used to tell "nothing
  /// here yet" apart from "nothing matches what you typed".
  bool get isUnfiltered =>
      query.trim().isEmpty && period == TripPeriod.all && status == null;

  TripHistoryFilter copyWith({
    String? query,
    TripPeriod? period,
    LrStatus? status,
    bool clearStatus = false,
  }) {
    return TripHistoryFilter(
      query: query ?? this.query,
      period: period ?? this.period,
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}

/// Only these two states mean "the trip is over" — anything else is either not
/// started or still running, and belongs on the Active tab.
const _finishedStates = {LrStatus.delivered, LrStatus.cancelled};

/// Finished trips, newest first.
///
/// [excludeLrIds] carries the LR ids currently on the Active tab so a row can
/// never show up in both places — an LR marked Delivered whose SIM trip has not
/// been closed yet is still live, and live wins.
///
/// Pure and synchronous on purpose: the whole filter runs over an already-loaded
/// list, so it is unit-testable without Riverpod and costs nothing per keystroke.
List<LorryReceipt> filterTripHistory(
  List<LorryReceipt> all, {
  TripHistoryFilter filter = const TripHistoryFilter(),
  Set<String> excludeLrIds = const {},
  DateTime? now,
}) {
  final cutoff = filter.period.cutoff(now ?? DateTime.now());
  final query = filter.query.trim().toLowerCase();

  final rows = <LorryReceipt>[];
  for (final lr in all) {
    if (excludeLrIds.contains(lr.id)) continue;
    if (!_finishedStates.contains(lr.status)) continue;
    if (filter.status != null && lr.status != filter.status) continue;
    if (cutoff != null) {
      final day = DateTime(lr.date.year, lr.date.month, lr.date.day);
      if (day.isBefore(cutoff)) continue;
    }
    if (query.isNotEmpty && !_matches(lr, query)) continue;
    rows.add(lr);
  }
  rows.sort((a, b) => b.date.compareTo(a.date));
  return rows;
}

/// Everything an operator would plausibly type to find a past trip: the LR
/// number, the truck, the driver, either end of the route, or either party.
bool _matches(LorryReceipt lr, String query) {
  final hay = [
    lr.number,
    lr.vehicle.number,
    lr.tripDriverName,
    lr.fromCity,
    lr.toCity,
    lr.route,
    lr.consignor.name,
    lr.consignee.name,
  ].join(' ').toLowerCase();
  return hay.contains(query);
}
