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
    final image = Image.asset(
      AppAssets.logo,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => _Fallback(height: height, light: light),
    );

    if (!wordmark) return image;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        image,
      ],
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
