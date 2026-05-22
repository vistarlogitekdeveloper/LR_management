import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class LabeledField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;

  const LabeledField({
    super.key,
    required this.label,
    this.required = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
