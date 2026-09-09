import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A lightweight shimmer placeholder shown while a screen's first data load is
/// in flight, so an empty API response and a still-loading one no longer look
/// identical.
///
/// Self-contained — no package dependency. A single repeating controller drives
/// a light band that a [ShaderMask] sweeps across the grey placeholder shapes in
/// the subtree, so every [ShimmerBox] under one [Shimmer] animates in unison.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  // Base (the resting placeholder colour) and the brighter sweep highlight.
  static const _base = Color(0xFFE9E6EF);
  static const _highlight = Color(0xFFF7F5FB);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value; // 0 → 1
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            // A moving highlight band. Stops are clamped to [0,1] and stay
            // non-decreasing because the base offsets are ordered.
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [_base, _highlight, _base],
              stops: [
                (t - 0.3).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// One grey placeholder block. Only meaningful inside a [Shimmer] ancestor,
/// which recolours it with the animated sweep.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Recoloured by the Shimmer ShaderMask; this is only the fallback tint.
        color: const Color(0xFFE9E6EF),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A block of shimmer rows approximating a loading table or list. Drop this in
/// wherever a list screen would otherwise show its "no records" text during the
/// initial fetch.
class ShimmerRows extends StatelessWidget {
  const ShimmerRows({super.key, this.rows = 8, this.showLeadingIcon = true});

  final int rows;

  /// Renders a small leading square (matching tables that lead with an action
  /// or icon column).
  final bool showLeadingIcon;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  if (showLeadingIcon) ...[
                    const ShimmerBox(width: 34, height: 20, radius: 6),
                    const SizedBox(width: 16),
                  ],
                  const Expanded(flex: 3, child: ShimmerBox()),
                  const SizedBox(width: 16),
                  const Expanded(flex: 2, child: ShimmerBox()),
                  const SizedBox(width: 16),
                  const Expanded(flex: 2, child: ShimmerBox()),
                  const SizedBox(width: 16),
                  const Expanded(flex: 1, child: ShimmerBox()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A block of shimmer cards for card-style/mobile lists and dashboards.
class ShimmerCards extends StatelessWidget {
  const ShimmerCards({super.key, this.cards = 4, this.height = 76});

  final int cards;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < cards; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              height: height,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  ShimmerBox(width: 160, height: 14),
                  ShimmerBox(width: 240, height: 12),
                  ShimmerBox(width: 100, height: 12),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
