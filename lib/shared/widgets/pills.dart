import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../models/lr_models.dart';

class StatusPill extends StatelessWidget {
  final LrStatus status;
  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final palette = switch (status) {
      LrStatus.delivered => (
        AppColors.ok,
        AppColors.ok.withValues(alpha: 0.14),
      ),
      LrStatus.inTransit => (
        AppColors.orange,
        AppColors.orange.withValues(alpha: 0.14),
      ),
      LrStatus.booked => (
        AppColors.plumLight,
        AppColors.plumLight.withValues(alpha: 0.14),
      ),
      LrStatus.cancelled => (
        AppColors.danger,
        AppColors.danger.withValues(alpha: 0.14),
      ),
    };
    return _Pill(text: status.label, fg: palette.$1, bg: palette.$2);
  }
}

class PayPill extends StatelessWidget {
  final PayType pay;
  const PayPill({super.key, required this.pay});

  @override
  Widget build(BuildContext context) {
    final fg = switch (pay) {
      PayType.tbb => AppColors.plum,
      PayType.tbr => AppColors.red,
      PayType.paid => AppColors.ok,
    };
    return _Pill(text: pay.label, fg: fg, bg: fg.withValues(alpha: 0.12));
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Pill({required this.text, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// "★ Special vehicle" (migration 254): a trip watched closely — badged on
/// every LR screen, the print and the tracking map.
class SpecialVehiclePill extends StatelessWidget {
  final bool compact;
  const SpecialVehiclePill({super.key, this.compact = false});

  static const color = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            color: Colors.white,
            size: compact ? 11 : 13,
          ),
          const SizedBox(width: 3),
          Text(
            compact ? 'SPECIAL' : 'Special vehicle',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 10 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
