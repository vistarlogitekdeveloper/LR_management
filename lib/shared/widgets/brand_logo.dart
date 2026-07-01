import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';

class BrandLogo extends StatelessWidget {
  final double height;
  final bool light;
  final bool wordmark;

  const BrandLogo({
    super.key,
    this.height = 30,
    this.light = false,
    this.wordmark = true,
  });

  @override
  Widget build(BuildContext context) {
    // wordmark: the full "Vi★tar" logo (app logo); otherwise the "S" symbol.
    return Image.asset(
      wordmark ? AppAssets.logo : AppAssets.logoSymbol,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => _Fallback(height: height, light: light),
    );
  }
}

class _Fallback extends StatelessWidget {
  final double height;
  final bool light;
  const _Fallback({required this.height, required this.light});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: height,
      height: height,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(height * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        'V',
        style: TextStyle(
          color: Colors.white,
          fontSize: height * 0.55,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
