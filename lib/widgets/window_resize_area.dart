import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// A widget that wraps content and provides resize handles for frameless windows.
/// Place this as the outermost widget in your window's body.
class WindowResizeArea extends StatelessWidget {
  final Widget child;
  final double resizeEdgeSize;

  const WindowResizeArea({
    super.key,
    required this.child,
    this.resizeEdgeSize = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        child,
        // Resize handles - positioned around edges
        // Top edge
        Positioned(
          top: 0,
          left: resizeEdgeSize,
          right: resizeEdgeSize,
          height: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeUp,
            edge: ResizeEdge.top,
          ),
        ),
        // Bottom edge
        Positioned(
          bottom: 0,
          left: resizeEdgeSize,
          right: resizeEdgeSize,
          height: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeDown,
            edge: ResizeEdge.bottom,
          ),
        ),
        // Left edge
        Positioned(
          top: resizeEdgeSize,
          bottom: resizeEdgeSize,
          left: 0,
          width: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeLeft,
            edge: ResizeEdge.left,
          ),
        ),
        // Right edge
        Positioned(
          top: resizeEdgeSize,
          bottom: resizeEdgeSize,
          right: 0,
          width: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeRight,
            edge: ResizeEdge.right,
          ),
        ),
        // Corners
        // Top-left
        Positioned(
          top: 0,
          left: 0,
          width: resizeEdgeSize,
          height: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeUpLeft,
            edge: ResizeEdge.topLeft,
          ),
        ),
        // Top-right
        Positioned(
          top: 0,
          right: 0,
          width: resizeEdgeSize,
          height: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeUpRight,
            edge: ResizeEdge.topRight,
          ),
        ),
        // Bottom-left
        Positioned(
          bottom: 0,
          left: 0,
          width: resizeEdgeSize,
          height: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeDownLeft,
            edge: ResizeEdge.bottomLeft,
          ),
        ),
        // Bottom-right
        Positioned(
          bottom: 0,
          right: 0,
          width: resizeEdgeSize,
          height: resizeEdgeSize,
          child: _ResizeHandle(
            cursor: SystemMouseCursors.resizeDownRight,
            edge: ResizeEdge.bottomRight,
          ),
        ),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final MouseCursor cursor;
  final ResizeEdge edge;

  const _ResizeHandle({required this.cursor, required this.edge});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        onPanStart: (_) => windowManager.startResizing(edge),
        behavior: HitTestBehavior.translucent,
        child: const SizedBox.expand(),
      ),
    );
  }
}
