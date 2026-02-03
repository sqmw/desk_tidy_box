# Hover 自动展开动画优化

## 问题

当前盒子在「收起模式」下鼠标悬浮自动展开/移出自动收起的体验不够丝滑，主要表现为：
- 窗口高度直接 `setSize` 跳变（从 50px 突然到展开高度）
- `Future.delayed` 串行等待导致快速移入/移出时出现竞态（晚到的异步回调反向覆盖当前状态）

## 解决方案

### 1) 物理窗口高度改为“跳变 + 内容动画”

在 Windows 上频繁 `setSize` 会产生明显卡顿和抖动，因此改为：
- **窗口高度只做一次性跳变**（避免卡顿）
- **内容区域做平滑 Reveal 动画**（视觉丝滑）

实现：`lib/services/window_height_animator.dart`

### 2) Hover 逻辑加 epoch 防竞态

在 `MouseRegion.onEnter/onExit` 中引入 `_hoverTransitionEpoch`：
- 每次 enter/exit 递增 epoch
- 异步 delay / 动画 await 之后检查 epoch 是否仍然匹配，不匹配则直接 return

这样可以避免「鼠标已经回来了但旧的 onExit 还在继续收起」这类问题。

实现：`lib/box_page.dart`

### 3) 内容区域改为统一的 Reveal 动画（更“优雅”）

以前内容区使用 `flutter_animate` 的链式动画（fade/slide/scale）叠加 `AnimatedAlign(heightFactor)`，在窗口高度变化时容易出现：
- 内容“抢跑”显示/消失（窗口还没来得及变化）
- 视觉上有突兀的跳变

现在改成 `BoxContentTransition`：
- 用 `heightFactor + opacity + translate + scale` 统一控制内容区出现/消失
- 内容仍保留在树里（不会因为 remove/reinsert 导致滚动位置等状态频繁丢失）

实现：`lib/widgets/box_content_transition.dart`

### 4) 布局稳定性优化（防“界面混乱”）

内容区高度改为基于 `LayoutBuilder` 的 **固定最大高度**，Reveal 采用 `Align(heightFactor)` 做裁剪显示，避免每一帧都触发布局抖动。

实现：`lib/box_page.dart`

### 5) 展开时延迟 1 帧显示内容

窗口高度跳变后，延迟约 1 帧再打开内容动画，避免“窗口还没稳住内容先显示”的瞬间混乱。

实现：`lib/box_page.dart`

## 相关文件

- `lib/services/window_height_animator.dart`
- `lib/box_page.dart`
- `lib/widgets/box_content_transition.dart`
