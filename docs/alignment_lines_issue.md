# 对齐线条功能问题记录

## 问题描述

在实现窗口拖拽时的对齐线条功能时，遇到了一个核心问题：**Flutter 在窗口拖拽时不会触发 UI 重绘**。

### 表现

1. 对齐检测逻辑正常工作（通过日志确认状态已更新）
2. `setState()` 被正确调用
3. 但在拖拽过程中，UI 不刷新，线条不显示
4. 松开鼠标后，UI 才会更新，但此时已经不需要显示线条了

### 根本原因

Flutter/Windows 的窗口拖拽机制：
- 当用户拖拽窗口时，Windows 进入了一个模态循环（modal loop）
- 在这个循环中，Flutter 的渲染管道被阻塞
- `setState()` 虽然被调用，但重建（rebuild）被延迟到拖拽结束后才执行

## 尝试过的方案

### 1. 使用 `onWindowMove` 回调 ❌
- **问题**：`box_page.dart` 的 `onWindowMove` 不会被调用
- **原因**：只有 `main.dart` 的监听器会收到事件

### 2. 使用 Timer 定时轮询 ❌
- **问题**：Timer 触发，`setState` 调用，但 UI 不刷新
- **原因**：拖拽时 Flutter 渲染被阻塞

### 3. 异步 Future 转同步 then() ❌
- **问题**：仍然无法在拖拽时刷新 UI
- **原因**：问题不在于异步，而在于渲染管道被阻塞

## 推荐解决方案

### 方案 A：使用 Win32 API 直接绘制（推荐） ✅

**优点：**
- 绕过 Flutter 渲染，直接在窗口上绘制
- 实时响应，无延迟
- 可以绘制到屏幕空间（跨窗口）

**实现步骤：**
1. 使用 `win32` 包或 FFI 调用 Windows API
2. 使用 `EnumWindows` 和 `GetWindowRect` 获取所有盒子窗口位置
3. 通过窗口标题或进程 PID 识别自己的窗口
4. 使用 `CreateWindowEx` 创建一个透明的置顶窗口（WS_EX_LAYERED | WS_EX_TRANSPARENT）
5. 在该窗口上使用 GDI+ 绘制对齐线条

**参考代码：**
```dart
import 'package:win32/win32.dart';

class AlignmentLineOverlay {
  int? _hwnd;
  
  void show(int x, int y, bool isVertical) {
    // Create or update transparent overlay window
    // Draw line using GDI+
  }
  
  void hide() {
    // Hide overlay window
  }
}
```

### 方案 B：使用 Platform View ⚠️

创建一个原生 Windows 控件来绘制线条，但这个方案较复杂且可能有性能问题。

### 方案 C：使用自定义 RenderObject ⚠️

尝试绕过 Widget 层直接操作渲染层，但不确定是否能解决拖拽时的阻塞问题。

## 临时状态

当前代码中：
- 对齐检测逻辑已实现（`onWindowMove`）
- 对齐线条渲染代码已注释（`lib/box_page.dart` 第 620-665 行）
- 状态变量保留（`_alignLeft`, `_alignRight`, `_alignTop`, `_alignBottom`）

## 下一步行动

1. 研究 `win32` 包的使用
2. 实现透明置顶窗口
3. 使用 GDI+ 绘制线条
4. 测试跨窗口绘制效果

## 相关资源

- [win32 package](https://pub.dev/packages/win32)
- [Creating Layered Windows (Microsoft Docs)](https://docs.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows)
- [GDI+ Graphics (Microsoft Docs)](https://docs.microsoft.com/en-us/windows/win32/gdiplus/-gdiplus-gdi-start)

## 更新日志

- 2026-01-18: 初次记录问题，禁用对齐线条功能
