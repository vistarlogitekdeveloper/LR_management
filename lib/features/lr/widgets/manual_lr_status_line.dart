import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../utils/manual_lr_entry.dart';
import '../utils/manual_lr_number.dart';

/// "✓ Available" / "checking…" / why it cannot be used.
class ManualLrStatusLine extends StatelessWidget {
  final ManualLrEntry? entry;
  const ManualLrStatusLine({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final (IconData icon, Color color, String text) = switch (e?.status) {
      ManualLrStatus.available => (
        Icons.check_circle_rounded,
        AppColors.ok,
        '${e!.number} is available',
      ),
      ManualLrStatus.checking => (
        Icons.hourglass_top_rounded,
        AppColors.slate,
        'Checking that no LR has it…',
      ),
      ManualLrStatus.taken => (
        Icons.cancel_rounded,
        AppColors.danger,
        e!.message ?? 'Already used',
      ),
      ManualLrStatus.unknown => (
        Icons.info_outline_rounded,
        AppColors.warn,
        e!.message ?? '',
      ),
      _ => (
        Icons.info_outline_rounded,
        e == null || (e.message ?? '').startsWith('Type the number')
            ? AppColors.slate
            : AppColors.danger,
        e?.message ?? 'Must start with $manualLrPrefix and be unique.',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
