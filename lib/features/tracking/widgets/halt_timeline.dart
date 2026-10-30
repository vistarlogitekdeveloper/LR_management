import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../data/tracking_repository.dart';

/// Every halt of the trip as a timeline, newest first (30 Oct 2026): when it
/// began and ended, how long, where, whether it was alerted, and the reason
/// given. Each halt is numbered like its pin on the map (H1 = the first halt).
class HaltTimeline extends StatelessWidget {
  final List<TripHalt> halts;

  /// "1 h" for a special vehicle, else "2 h" — the shortest halt recorded.
  final String recordedFrom;
  const HaltTimeline({
    super.key,
    required this.halts,
    this.recordedFrom = '2 h',
  });

  @override
  Widget build(BuildContext context) {
    if (halts.isEmpty) {
      return Text(
        'No halts of $recordedFrom or more on this trip.',
        style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
      );
    }
    final total = halts.fold<double>(0, (s, h) => s + h.hours);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${halts.length} halt${halts.length == 1 ? '' : 's'} · '
          '${haltHoursLabel(total)} standing in all',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = halts.length - 1; i >= 0; i--)
          _HaltEntry(index: i + 1, halt: halts[i], last: i == 0),
      ],
    );
  }
}

class _HaltEntry extends StatelessWidget {
  final int index;
  final TripHalt halt;
  final bool last;
  const _HaltEntry({
    required this.index,
    required this.halt,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final h = halt;
    final color = h.ongoing
        ? (h.overAlertLimit ? AppColors.danger : AppColors.warn)
        : (h.overAlertLimit ? AppColors.danger : AppColors.slate);
    final range = [
      if (h.startedAt != null) formatDateTime(h.startedAt!),
      h.ongoing
          ? 'now'
          : (h.endedAt != null ? formatDateTime(h.endedAt!) : 'signal lost'),
    ].join('  →  ');
    final place = [
      h.city,
      h.address,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' — ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  'H$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.slate.withValues(alpha: 0.25),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        h.durationLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: color,
                        ),
                      ),
                      if (h.ongoing) _tag('STANDING NOW', AppColors.danger),
                      if (h.alerted) _tag('ALERTED', AppColors.orange),
                      if (h.acknowledged)
                        _tag(
                          (h.ackReason?.label ?? 'Acknowledged').toUpperCase(),
                          AppColors.ok,
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    range,
                    style: const TextStyle(fontSize: 12, color: AppColors.ink),
                  ),
                  if (place.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        place,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.slate,
                        ),
                      ),
                    ),
                  if ((h.ackNote ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '“${h.ackNote}”',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: AppColors.slate,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: c),
    ),
  );
}

/// "3 h 40 m" from hours.
String haltHoursLabel(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m m';
  return m == 0 ? '$h h' : '$h h $m m';
}

/// A halt's pin on the trail map: "H1", red once alerted, amber while it
/// stands, grey when it is over.
class HaltPin extends StatelessWidget {
  final int index;
  final TripHalt halt;
  const HaltPin({super.key, required this.index, required this.halt});

  @override
  Widget build(BuildContext context) {
    final color = halt.overAlertLimit
        ? AppColors.danger
        : (halt.ongoing ? AppColors.warn : AppColors.slate);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        'H$index',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
