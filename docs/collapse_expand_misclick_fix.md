# 收拢/展开按钮误触 Bug 修复

## 问题描述

收拢状态下，点击盒子头部的任意位置会错误触发展开，但固定状态(isPinned=true)时不会发生。

## 根本原因

1. `_BoxHeader` 中的 `GestureDetector` 使用 `HitTestBehavior.translucent`
2. 点击头部触发 `onPanStart`（即使没有真正拖动）
3. `onPanStart` 调用 `onDragStart?.call()`
4. `onDragStart` 回调包含自动展开逻辑：
```dart
onDragStart: () async {
  setState(() => _isDragging = true);
  if (_isCollapsed) {
    // 自动展开窗口...
  }
}
```
5. 固定状态时 `onPanStart` 直接 return，不调用 `onDragStart`，故无此问题

## 解决方案

移除 `onDragStart` 中的自动展开逻辑：

```dart
// 修改后
onDragStart: () {
  setState(() => _isDragging = true);
  _loadOtherBounds();
},
```

## 修改文件

- `lib/box_page.dart` - 第541行附近，移除 `onDragStart` 回调中的自动展开代码

## 修复日期

2026-01-20
