import 'dart:ui';

import 'package:flutter/material.dart';

/// A container with frosted glass / acrylic / mica effect.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double blurSigma;
  final BorderRadius? borderRadius;
  final BoxBorder? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.opacity = 0.2,
    this.blurSigma = 18,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.black : Colors.white;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
