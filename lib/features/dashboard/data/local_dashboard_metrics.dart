import '../../../shared/models/lr_models.dart';
import '../../reports/data/reports_repository.dart';

/// Client-side stand-in for the server's `/reports/dashboard` → `metrics` block.
///
/// WHY THIS EXISTS: the Flutter web bundle and the API deploy independently, so
/// a build can reach production ahead of the backend that serves `metrics`. This
/// keeps the tiles populated through that window instead of showing a screen of
/// em-dashes. Once the API responds with `metrics`, this is never called.
///
/// It is deliberately a DEGRADED copy, not a second implementation:
///   - `total` can only ever cover the LRs this client fetched, whereas the
///     server counts every row.
///   - scopes use the device clock/timezone; the server always uses IST.
///   - "completed" scopes by LR date, because the list model carries no
///     delivered_at.
/// Treat the server as the source of truth for these numbers — if the two
/// disagree, the server is right.
Map<String, MetricScopes> localDashboardMetrics(List<LorryReceipt> lrs) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);

  bool isToday(DateTime d) =>
      d.year == now.year && d.month == now.month && d.day == now.day;
  bool inMonth(DateTime d) => !d.isBefore(monthStart);
  bool live(LorryReceipt lr) => lr.status != LrStatus.cancelled;

  // Counts rows across the three scopes. `dateOf` drives the scoping; when it
  // returns null the row can only land in `total`, and only if the total does
  // not itself require the event to have happened.
  MetricScopes counted(
    Iterable<LorryReceipt> rows,
    DateTime? Function(LorryReceipt) dateOf, {
    required bool totalRequiresDate,
  }) {
    var today = 0, mtd = 0, total = 0;
    for (final lr in rows) {
      final d = dateOf(lr);
      if (d != null || !totalRequiresDate) total++;
      if (d == null) continue;
      if (isToday(d)) today++;
      if (inMonth(d)) mtd++;
    }
    return MetricScopes(
      today: today.toDouble(),
      mtd: mtd.toDouble(),
      total: total.toDouble(),
    );
  }

  // Mirrors the server's COUNT(DISTINCT (vehicle, day)): a truck running two
  // LRs on one day is one placement/dispatch, not two.
  MetricScopes vehicleDays(DateTime? Function(LorryReceipt) dateOf) {
    final today = <String>{}, mtd = <String>{}, total = <String>{};
    for (final lr in lrs) {
      if (!live(lr)) continue;
      final v = lr.vehicle.number.trim().toUpperCase();
      if (v.isEmpty) continue;
      final d = dateOf(lr);
      if (d == null) continue;
      final key = '$v|${d.year}-${d.month}-${d.day}';
      total.add(key);
      if (isToday(d)) today.add(key);
      if (inMonth(d)) mtd.add(key);
    }
    return MetricScopes(
      today: today.length.toDouble(),
      mtd: mtd.length.toDouble(),
      total: total.length.toDouble(),
    );
  }

  MetricScopes summed(bool Function(LorryReceipt) test) {
    var today = 0.0, mtd = 0.0, total = 0.0;
    for (final lr in lrs) {
      if (!test(lr)) continue;
      final v = lr.freight.balance;
      total += v;
      if (isToday(lr.date)) today += v;
      if (inMonth(lr.date)) mtd += v;
    }
    return MetricScopes(today: today, mtd: mtd, total: total);
  }

  return {
    'lrs_booked': counted(lrs, (lr) => lr.date, totalRequiresDate: false),
    'vehicles_placed': vehicleDays((lr) => lr.inDateTime),
    // The server also falls back to dispatched_at here; the list model does not
    // carry it, so an LR moved to In Transit without a gate time keyed in is
    // missed by this approximation.
    'vehicles_dispatched': vehicleDays((lr) => lr.outDateTime),
    'trips_in_transit': counted(
      lrs.where((lr) => lr.status == LrStatus.inTransit),
      (lr) => lr.date,
      totalRequiresDate: false,
    ),
    // Scoped by LR date, not completion date (no delivered_at on the model), so
    // "today" here means "booked today and now delivered".
    'trips_completed': counted(
      lrs.where((lr) => lr.status == LrStatus.delivered),
      (lr) => lr.date,
      totalRequiresDate: false,
    ),
    'pending_delivery': counted(
      lrs.where(
        (lr) => lr.status == LrStatus.booked || lr.status == LrStatus.inTransit,
      ),
      (lr) => lr.date,
      totalRequiresDate: false,
    ),
    'pending_freight': summed((lr) => live(lr) && lr.freight.balance > 0),
  };
}
