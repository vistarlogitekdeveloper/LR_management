import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class AppTopbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const AppTopbar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(78);

  @override
  Widget build(BuildContext context) {
    // Compact on phones so the header doesn't eat vertical space — smaller
    // padding/title and a single-line (ellipsised) subtitle.
    final mobile = MediaQuery.of(context).size.width < 600;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: mobile ? 18 : 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: mobile ? 2 : 4),
          Text(
            subtitle!,
            maxLines: mobile ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: mobile ? 12 : 13,
              color: AppColors.slate,
            ),
          ),
        ],
      ],
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 16 : 28,
        vertical: mobile ? 10 : 16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      // On phones, actions can't share a single line with the title without
      // overflowing — stack the title and wrap the actions below.
      child: mobile && actions.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleBlock,
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: titleBlock),
                for (final action in actions) ...[
                  const SizedBox(width: 10),
                  action,
                ],
              ],
            ),
    );
  }
}
