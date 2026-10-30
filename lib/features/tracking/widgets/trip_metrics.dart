import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/trip_record.dart';
import 'halt_timeline.dart';

/// A finished trip's numbers on its History row (server: /tracking/history):
/// how long it took, the route distance, its halts (red when one was alerted),
/// driver changes, and whether it was tracked at all.
class TripMetrics extends StatelessWidget {
  final TripRecord t;
  const TripMetrics({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (t.tripHours != null)
        _chip(
          Icons.timelapse_rounded,
          haltHoursLabel(t.tripHours!),
          AppColors.slate,
        ),
      if (t.routeKm != null)
        _chip(
          Icons.straighten_rounded,
          '${t.routeKm!.round()} km',
          AppColors.slate,
        ),
      if (t.halts > 0)
        _chip(
          Icons.pause_circle_filled_rounded,
          '${t.halts} halt${t.halts == 1 ? '' : 's'} · ${haltHoursLabel(t.haltHours)}',
          t.haltAlerted ? AppColors.danger : AppColors.warn,
        )
      else if (t.tracked)
        _chip(Icons.check_circle_outline_rounded, 'No halts', AppColors.ok),
      if (t.driverChanges > 0)
        _chip(
          Icons.swap_horiz_rounded,
          '${t.driverChanges} driver change${t.driverChanges == 1 ? '' : 's'}',
          AppColors.plum,
        ),
      if (!t.tracked)
        _chip(Icons.location_disabled_rounded, 'Not tracked', AppColors.slate),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(IconData icon, String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
        ),
      ],
    ),
  );
}
