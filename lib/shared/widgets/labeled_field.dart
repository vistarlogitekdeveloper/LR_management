import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class LabeledField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;

  /// When set, a red validation message is shown below the field — used to
  /// flag a missing mandatory field after a failed save.
  final String? errorText;

  const LabeledField({
    super.key,
    required this.label,
    this.required = false,
    required this.child,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
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
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 13,
                  color: AppColors.red,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
