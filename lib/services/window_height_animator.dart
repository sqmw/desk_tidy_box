import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:window_manager/window_manager.dart';

class WindowHeightAnimator {
  WindowHeightAnimator(this._windowManager, {required TickerProvider vsync})
      : _vsync = vsync;

  final WindowManager _windowManager;
  final TickerProvider _vsync;

  int _epoch = 0;
  AnimationController? _controller;
  VoidCallback? _listener;
  bool _disposed = false;

  void cancel() {
    _epoch++;
    _controller?.stop();
    _removeListener();
  }

  void dispose() {
    _disposed = true;
    _removeListener();
    _controller?.dispose();
  }

  void _removeListener() {
    final listener = _listener;
    if (listener == null) return;
    _controller?.removeListener(listener);
    _listener = null;
  }

  Future<void> animateTo({
    required double targetHeight,
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final startSize = await _windowManager.getSize();
    final startHeight = startSize.height;
    final width = startSize.width;

    if ((startHeight - targetHeight).abs() < 0.5) {
      await _windowManager.setSize(Size(width, targetHeight));
      return;
    }

    _controller ??= AnimationController(vsync: _vsync);
    _controller!.duration = duration;
    _removeListener();

    final animation = CurvedAnimation(parent: _controller!, curve: curve);
    _listener = () {
      if (_epoch != epoch) return;
      final t = animation.value;
      final nextHeight = lerpDouble(startHeight, targetHeight, t) ?? targetHeight;
      _windowManager.setSize(Size(width, nextHeight));
    };
    _controller!.addListener(_listener!);
    try {
      await _controller!.forward(from: 0);
      if (_epoch == epoch) {
        await _windowManager.setSize(Size(width, targetHeight));
      }
    } finally {
      _removeListener();
    }
  }

  Future<void> jumpTo(double targetHeight) async {
    cancel();
    if (_disposed) return;
    final size = await _windowManager.getSize();
    await _windowManager.setSize(Size(size.width, targetHeight));
  }
}
