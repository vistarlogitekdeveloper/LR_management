import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// How recent a trip's last location fix is (30 Oct 2026). SIM fixes arrive
/// every ~15–20 min, so an hour without one is already worth a look.
enum Freshness {
  /// A fix within the last hour.
  live,

  /// 1–6 h without a fix.
  delayed,

  /// 6–24 h without a fix.
  lost,

  /// Over a day without a fix.
  noSignal,

  /// No fix yet.
  awaiting,
}

Freshness freshnessOf(DateTime? lastFix, {DateTime? now}) {
  if (lastFix == null) return Freshness.awaiting;
  final age = (now ?? DateTime.now()).difference(lastFix);
  if (age <= const Duration(hours: 1)) return Freshness.live;
  if (age <= const Duration(hours: 6)) return Freshness.delayed;
  if (age <= const Duration(hours: 24)) return Freshness.lost;
  return Freshness.noSignal;
}

extension FreshnessX on Freshness {
  String get label => switch (this) {
    Freshness.live => 'Live',
    Freshness.delayed => 'Delayed 1h+',
    Freshness.lost => 'Signal lost 6h+',
    Freshness.noSignal => 'No signal 24h+',
    Freshness.awaiting => 'Awaiting first fix',
  };

  Color get color => switch (this) {
    Freshness.live => AppColors.ok,
    Freshness.delayed => AppColors.warn,
    Freshness.lost => AppColors.orange,
    Freshness.noSignal => AppColors.slate,
    Freshness.awaiting => AppColors.slate,
  };
}

/// A small coloured dot with the freshness label, for lists and panels.
class FreshnessTag extends StatelessWidget {
  final Freshness freshness;
  const FreshnessTag(this.freshness, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = freshness.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          freshness.label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
        ),
      ],
    );
  }
}
