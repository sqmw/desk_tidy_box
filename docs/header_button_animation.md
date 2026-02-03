# Header 按钮动画优化

## 问题

原来的 header 按钮显示/隐藏动画效果不够平滑：
- 仅使用 `AnimatedOpacity` 做透明度变化
- 按钮区域不会收缩，即使不可见也占用空间

## 解决方案

参考 `desk_tidy_sticky` 项目中 `StickyNoteCard` 的实现，采用三层动画组合：

```dart
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
        child: /* 按钮内容 */,
      ),
    ),
  ),
),
```

### 组件说明

1. **AnimatedSize** - 控制宽度从 0 到自然宽度的动画
2. **SizedBox with conditional width** - 当隐藏时宽度为 0
3. **IgnorePointer** - 隐藏时忽略点击事件
4. **AnimatedOpacity** - 透明度渐变动画

## 相关文件

- `lib/widgets/box_header.dart` - `BoxHeader` 组件
- `lib/widgets/hover_state_builder.dart` - 从 `desk_tidy_sticky` 复制的 hover 状态管理组件

## 参考

- `desk_tidy_sticky/lib/pages/overlay/sticky_note_card.dart`
- `desk_tidy_sticky/lib/widgets/hover_state_builder.dart`
