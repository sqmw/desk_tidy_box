import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../box_prefs.dart';

class BoxHeader extends StatelessWidget {
  const BoxHeader({
    super.key,
    required this.title,
    required this.hovering,
    required this.isPinned,
    required this.isCollapsed,
    required this.displayMode,
    required this.onToggleDisplayMode,
    required this.onToggleCollapsed,
    required this.onMenu,
    required this.onRefresh,
    required this.onClose,
    this.onDragStart,
    this.onDragEnd,
  });

  final String title;
  final bool hovering;
  final bool isPinned;
  final bool isCollapsed;
  final BoxDisplayMode displayMode;
  final VoidCallback onToggleDisplayMode;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onMenu;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showButtons = hovering;

    return SizedBox(
      height: 44,
      child: GestureDetector(
        // Allow dragging the window by the header.
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          if (isPinned) return;
          onDragStart?.call();
          windowManager.startDragging();
        },
        onPanEnd: (_) => onDragEnd?.call(),
        onPanCancel: () => onDragEnd?.call(),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              title == '文件夹' ? Icons.folder : Icons.description,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: SizedBox(
                width: showButtons ? null : 0,
                child: IgnorePointer(
                  ignoring: !showButtons,
                  child: AnimatedOpacity(
                    opacity: showButtons ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      // Absorb pan events to prevent window dragging when clicking buttons.
                      onPanStart: (_) {},
                      onPanUpdate: (_) {},
                      onPanEnd: (_) {},
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: isCollapsed ? '展开盒子' : '收起盒子',
                            onPressed: onToggleCollapsed,
                            icon: Icon(
                              isCollapsed
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                          ),
                          IconButton(
                            tooltip: displayMode == BoxDisplayMode.grid
                                ? '列表视图'
                                : '网格视图',
                            onPressed: onToggleDisplayMode,
                            icon: Icon(
                              displayMode == BoxDisplayMode.grid
                                  ? Icons.view_list
                                  : Icons.grid_view,
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新',
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: '菜单',
                            onPressed: onMenu,
                            icon: const Icon(Icons.more_vert),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

