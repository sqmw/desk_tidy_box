import 'dart:ui';

import 'package:flutter/material.dart';

class BoxContentTransition extends StatelessWidget {
  const BoxContentTransition({
    super.key,
    required this.visible,
    required this.maxHeight,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeOutCubic,
  });

  final bool visible;
  final double maxHeight;
  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: curve,
      tween: Tween(end: visible ? 1.0 : 0.0),
      builder: (context, t, child) {
        final opacity = Curves.easeOut.transform(t);
        final dy = lerpDouble(-10, 0, t) ?? 0;
        final scale = lerpDouble(0.985, 1.0, t) ?? 1.0;

        return IgnorePointer(
          ignoring: t < 0.01,
          child: SizedBox(
            height: maxHeight,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: t,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
