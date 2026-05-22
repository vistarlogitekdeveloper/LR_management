import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../models/lr_models.dart';

class StatusPill extends StatelessWidget {
  final LrStatus status;
  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final palette = switch (status) {
      LrStatus.delivered => (AppColors.ok, AppColors.ok.withValues(alpha: 0.14)),
      LrStatus.inTransit => (AppColors.orange, AppColors.orange.withValues(alpha: 0.14)),
      LrStatus.booked => (AppColors.plumLight, AppColors.plumLight.withValues(alpha: 0.14)),
      LrStatus.cancelled => (AppColors.danger, AppColors.danger.withValues(alpha: 0.14)),
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
      PayType.toPay => AppColors.red,
      PayType.paid => AppColors.ok,
      PayType.foc => AppColors.slate,
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
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
