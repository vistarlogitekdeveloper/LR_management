import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum BtnKind { primary, ghost, soft, danger }

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final bool small;
  final bool expanded;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = BtnKind.primary,
    this.small = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide? side;
    List<BoxShadow>? shadow;

    switch (kind) {
      case BtnKind.primary:
        bg = AppColors.plum;
        fg = AppColors.white;
        shadow = [
          BoxShadow(
            color: AppColors.plum.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ];
        break;
      case BtnKind.ghost:
        bg = AppColors.white;
        fg = AppColors.plum;
        side = const BorderSide(color: AppColors.line, width: 1.5);
        break;
      case BtnKind.soft:
        bg = AppColors.plum.withValues(alpha: 0.08);
        fg = AppColors.plum;
        break;
      case BtnKind.danger:
        bg = AppColors.danger;
        fg = AppColors.white;
        break;
    }

    final padding = small
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 13);

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: side != null ? Border.fromBorderSide(side) : null,
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: small ? 15 : 17, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: small ? 12.5 : 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: child) : child;
  }
}
