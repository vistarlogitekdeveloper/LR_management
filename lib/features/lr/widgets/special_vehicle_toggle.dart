import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pills.dart';

/// The "Special vehicle" switch at the top of Create LR (migration 254). A
/// special vehicle is badged on every LR screen and the print, filterable in
/// tracking and reports, and its halts are alerted from 1 hour (5 h otherwise).
class SpecialVehicleToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const SpecialVehicleToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const c = SpecialVehiclePill.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: value ? c.withValues(alpha: 0.08) : AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? c : AppColors.line,
          width: value ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                value ? Icons.star_rounded : Icons.star_border_rounded,
                color: value ? c : AppColors.slate,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Special vehicle',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: value ? c : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Track this trip closely: marked on every screen and the '
                      'print, and a halt of 1 hour or more is emailed.',
                      style: TextStyle(fontSize: 12, color: AppColors.slate),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('special-vehicle'),
                value: value,
                activeThumbColor: c,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
