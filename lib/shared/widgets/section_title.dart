import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class SectionTitle extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? trailing;

  const SectionTitle({
    super.key,
    this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.plum.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: AppColors.plum),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
