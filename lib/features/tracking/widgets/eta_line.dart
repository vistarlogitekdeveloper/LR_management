import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../data/trip_eta.dart';

/// "ETA 30 Oct, 6:40 PM · running 2 h 20 m late" on the tracking panel.
class EtaLine extends StatelessWidget {
  final TripEta eta;
  const EtaLine({super.key, required this.eta});

  @override
  Widget build(BuildContext context) {
    final late = eta.late;
    final color = late ? AppColors.danger : AppColors.ok;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            late
                ? Icons.running_with_errors_rounded
                : Icons.flag_circle_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ETA ${formatDateTime(eta.etaAt!)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  late
                      ? 'Running about ${minutesLabel(eta.lateByMin)} late'
                            '${eta.plannedArrivalAt != null ? ' (planned ${formatDateTime(eta.plannedArrivalAt!)})' : ''}.'
                      : (eta.plannedArrivalAt != null
                            ? 'On time (planned ${formatDateTime(eta.plannedArrivalAt!)}).'
                            : 'Estimated from the last location and the road route.'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.slate,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
