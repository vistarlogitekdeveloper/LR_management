import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../data/driver_change.dart';

/// The driver handovers of a trip, newest first: who handed over to whom,
/// when, where the truck was, and the note.
class DriverHistory extends StatelessWidget {
  final List<DriverChange> changes;
  const DriverHistory({super.key, required this.changes});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final c in changes.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              radius: 15,
              backgroundColor: Color(0x1A7A1F6E),
              child: Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: AppColors.plum,
              ),
            ),
            title: Text(
              '${c.fromName ?? 'No driver'} → ${c.toName ?? '—'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if (c.changedAt != null) formatDateTime(c.changedAt!),
                if ((c.city ?? '').isNotEmpty) 'at ${c.city}',
                if (c.fromLrEdit) 'via LR edit',
                if ((c.note ?? '').isNotEmpty) '“${c.note}”',
              ].join(' · '),
            ),
          ),
      ],
    );
  }
}
