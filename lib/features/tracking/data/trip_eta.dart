/// Expected arrival for a running trip (server: trackingController.etaOf).
/// The server stretches road times for a loaded truck and allows 1 h before it
/// calls a trip late.
class TripEta {
  final DateTime? etaAt;
  final double? remainingKm;
  final int? remainingMin;
  final DateTime? plannedArrivalAt;
  final int lateByMin;

  const TripEta({
    this.etaAt,
    this.remainingKm,
    this.remainingMin,
    this.plannedArrivalAt,
    this.lateByMin = 0,
  });

  bool get late => lateByMin > 0;

  static TripEta? fromJson(Object? j) {
    if (j is! Map) return null;
    DateTime? dt(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    final eta = dt(j['eta_at']);
    if (eta == null) return null;
    return TripEta(
      etaAt: eta,
      remainingKm: (j['remaining_km'] as num?)?.toDouble(),
      remainingMin: (j['remaining_min'] as num?)?.toInt(),
      plannedArrivalAt: dt(j['planned_arrival_at']),
      lateByMin: (j['late_by_min'] as num?)?.toInt() ?? 0,
    );
  }
}

/// "2 h 20 m", "45 m"
String minutesLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m m';
  return m == 0 ? '$h h' : '$h h $m m';
}
