import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Says, before the button is pressed, exactly what the change will do.
class ChangeDriverEffects extends StatelessWidget {
  final String from;
  final String to;
  const ChangeDriverEffects({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.45);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What happens',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text("• $from's phone stops being tracked.", style: style),
          Text(
            "• Tracking starts on $to's phone — $to gets a consent SMS to approve.",
            style: style,
          ),
          const Text(
            '• A halt the truck is in now is closed as "Driver changed" — no halt '
            'alert for the handover.',
            style: style,
          ),
          const Text(
            '• Other open LRs on this truck with the same driver change too.',
            style: style,
          ),
        ],
      ),
    );
  }
}
