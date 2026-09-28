import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';

/// Consent status chip, shared by the fleet map, the trip-history list and the
/// per-LR trail screen.
class ConsentBadge extends StatelessWidget {
  final String? status;
  const ConsentBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = (status ?? '').toUpperCase();
    late Color bg;
    late Color fg;
    late String label;
    if (s == 'ALLOWED') {
      bg = AppColors.ok.withValues(alpha: 0.14);
      fg = AppColors.ok;
      label = 'Consent OK';
    } else if (s.contains('PENDING') || s.contains('NOT')) {
      bg = AppColors.warn.withValues(alpha: 0.16);
      fg = AppColors.warn;
      label = 'Consent pending';
    } else if (s.isEmpty) {
      bg = AppColors.line;
      fg = AppColors.slate;
      label = '—';
    } else {
      bg = AppColors.danger.withValues(alpha: 0.14);
      fg = AppColors.danger;
      label = status!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// Coarse "how long ago" label for a location fix. SIM fixes land every ~15-20
/// minutes, so minute-level precision is all the detail that means anything.
String relTime(DateTime? t) {
  if (t == null) return 'no time';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// Floating status capsule used over the map.
class TrackingPill extends StatelessWidget {
  final String text;
  const TrackingPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.slate),
      ),
    );
  }
}

/// Designed error state with a retry — never a red error box.
class TrackingErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const TrackingErrorBox({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      // Scrollable so the message and its retry stay reachable on a short
      // viewport and at large text scales.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.slate,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.slate),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Designed empty state: an illustration, a human sentence and (optionally) the
/// one action that resolves it.
class TrackingEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const TrackingEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.plum.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.plum),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.slate),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              AppButton(
                label: actionLabel!,
                icon: Icons.filter_alt_off_rounded,
                kind: BtnKind.soft,
                small: true,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
