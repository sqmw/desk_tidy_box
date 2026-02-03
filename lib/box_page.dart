import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

import 'glass_container.dart';
import 'widgets/window_resize_area.dart';
import 'shared_prefs_helper.dart';
import 'box_prefs.dart';
import 'services/window_height_animator.dart';
import 'models/box_type.dart';
import 'widgets/box_header.dart';
import 'widgets/box_grid.dart';
import 'widgets/box_list.dart';
import 'widgets/box_content_transition.dart';

class BoxPage extends StatefulWidget {
  final BoxType type;
  final String desktopPath;

  const BoxPage({super.key, required this.type, required this.desktopPath});

  @override
  State<BoxPage> createState() => _BoxPageState();
}


class _BoxPageState extends State<BoxPage>
    with WindowListener, TickerProviderStateMixin {
  bool _hovering = false;
  bool _loading = true;
  String? _error;
  List<FileSystemEntity> _entries = const [];
  String _desktopPath = '';
  late final WindowHeightAnimator _heightAnimator;
  int _hoverTransitionEpoch = 0;

  // Alignment state
  BoxBounds? _otherBounds;
  DateTime? _lastMoveCheck;
  // Visual state
  bool _alignLeft = false;
  bool _alignRight = false;
  bool _alignTop = false;
  bool _alignBottom = false;

  // Display mode
  BoxDisplayMode _displayMode = BoxDisplayMode.grid;
  bool _isPinned = false;
  bool _isCollapsed = false;
  bool _showContent = true; // Controls visibility of the content below header
  Size? _expandedSize; // Store size before collapsing

  // Interaction state guards
  bool _isMenuOpen = false;
  bool _isDragging = false;
  static const double _headerHeight = 44;

  @override
  void initState() {
    super.initState();
    _heightAnimator = WindowHeightAnimator(windowManager, vsync: this);
    windowManager.addListener(this);
    // Mark this box as running
    BoxPrefs().saveRunning(widget.type.name, true);
    _init();
    _loadOtherBounds();
  }

  @override
  void dispose() {
    // Mark this box as not running
    BoxPrefs().saveRunning(widget.type.name, false);
    _heightAnimator.cancel();
    _heightAnimator.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _init() async {
    final desktopPath = widget.desktopPath.isNotEmpty
        ? widget.desktopPath
        : await _getDesktopPath();
    if (!mounted) return;

    // Load display mode
    final mode = await BoxPrefs().loadDisplayMode(widget.type.name);
    final pinned = await BoxPrefs().loadPinned(widget.type.name);
    final collapsed = await BoxPrefs().loadCollapsed(widget.type.name);

    setState(() {
      _desktopPath = desktopPath;
      _displayMode = mode;
      _isPinned = pinned;
      _isCollapsed = collapsed;
      _showContent = !collapsed;
    });

    // Get current window size and manage collapse state
    final currentSize = await windowManager.getSize();

    if (collapsed) {
      // If starting collapsed, save current size as expanded size (or use default)
      _expandedSize = currentSize.height > 100
          ? currentSize
          : const Size(500, 300);
      // Then shrink window
      await windowManager.setSize(Size(currentSize.width, 50));
    } else {
      // If starting expanded, save current size
      _expandedSize = currentSize;
      // Ensure window is tall enough for content
      if (currentSize.height < 100) {
        _expandedSize = const Size(500, 300);
        await windowManager.setSize(_expandedSize!);
      }
    }

    await _refresh();
  }

  @override
  void onWindowFocus() {
    _loadOtherBounds();
  }

  Future<void> _loadOtherBounds() async {
    final otherType = widget.type == BoxType.folders
        ? BoxType.files
        : BoxType.folders;

    // Only load bounds if the other box is actually running
    final isOtherRunning = await BoxPrefs().loadRunning(otherType.name);
    if (!isOtherRunning) {
      if (mounted) {
        setState(() => _otherBounds = null);
      }
      return;
    }

    final bounds = await BoxPrefs().loadBounds(otherType.name);
    if (mounted) {
      setState(() => _otherBounds = bounds);
    }
  }

  @override
  void onWindowMove() async {
    if (_otherBounds == null) return;

    // Throttle: Limit UI updates to ~60 FPS
    final now = DateTime.now();
    if (_lastMoveCheck != null &&
        now.difference(_lastMoveCheck!).inMilliseconds < 16) {
      return;
    }
    _lastMoveCheck = now;

    final rect = await windowManager.getBounds();
    final otherX = _otherBounds!.x.toDouble();
    final otherY = _otherBounds!.y.toDouble();
    final otherW = _otherBounds!.width.toDouble();
    final otherH = _otherBounds!.height.toDouble();
    final otherR = otherX + otherW;
    final otherB = otherY + otherH;

    const kThreshold = 20.0;

    // Calculate deltas for all 4 vertical edges (Left/Right)
    final dLL = (rect.left - otherX).abs();
    final dLR = (rect.left - otherR).abs();
    final dRL = (rect.right - otherX).abs();
    final dRR = (rect.right - otherR).abs();

    // Calculate deltas for all 4 horizontal edges (Top/Bottom)
    final dTT = (rect.top - otherY).abs();
    final dTB = (rect.top - otherB).abs();
    final dBT = (rect.bottom - otherY).abs();
    final dBB = (rect.bottom - otherB).abs();

    // Find the minimum distance
    double minD = kThreshold + 1;
    String bestMatch = '';

    void check(double d, String type) {
      if (d < minD) {
        minD = d;
        bestMatch = type;
      }
    }

    check(dLL, 'LL');
    check(dLR, 'LR');
    check(dRL, 'RL');
    check(dRR, 'RR');
    check(dTT, 'TT');
    check(dTB, 'TB');
    check(dBT, 'BT');
    check(dBB, 'BB');

    // Reset all
    bool newAL = false;
    bool newAR = false;
    bool newAT = false;
    bool newAB = false;

    if (minD < kThreshold) {
      // We have a winner - show ONLY that line
      if (bestMatch == 'LL' || bestMatch == 'LR') {
        newAL = true; // My Left aligns
      } else if (bestMatch == 'RL' || bestMatch == 'RR') {
        newAR = true; // My Right aligns
      } else if (bestMatch == 'TT' || bestMatch == 'TB') {
        newAT = true; // My Top aligns
      } else if (bestMatch == 'BT' || bestMatch == 'BB') {
        newAB = true; // My Bottom aligns
      }
    }

    if (newAL != _alignLeft ||
        newAR != _alignRight ||
        newAT != _alignTop ||
        newAB != _alignBottom) {
      setState(() {
        _alignLeft = newAL;
        _alignRight = newAR;
        _alignTop = newAT;
        _alignBottom = newAB;
      });
    }
  }

  Future<String> _getDesktopPath() async {
    if (!Platform.isWindows) return '';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    if (userProfile.isEmpty) return '';
    return '$userProfile\\Desktop';
  }

  List<String> _desktopLocations(String primary) {
    final locations = <String>[primary];
    // Add public desktop
    final publicDesktop = 'C:\\Users\\Public\\Desktop';
    if (Directory(publicDesktop).existsSync()) {
      locations.add(publicDesktop);
    }
    return locations;
  }

  @override
  void onWindowMoved() {
    _loadOtherBounds();
    if (_isDragging) {
      if (mounted) setState(() => _isDragging = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = _loadDesktopEntries();
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _entries = const [];
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<FileSystemEntity> _loadDesktopEntries() {
    if (_desktopPath.isEmpty) return const [];
    final dirs = _desktopLocations(_desktopPath);
    final seen = <String>{};
    final entries = <FileSystemEntity>[];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync()) {
        if (!seen.add(entity.path)) continue;
        final name = path.basename(entity.path);
        final lower = name.toLowerCase();
        if (lower == 'desktop.ini' || lower == 'thumbs.db') continue;
        if (widget.type == BoxType.folders) {
          if (entity is Directory) entries.add(entity);
        } else {
          if (entity is! File) continue;
          final ext = path.extension(entity.path).toLowerCase();
          // Keep "apps" out of this box
          if (ext == '.lnk' ||
              ext == '.exe' ||
              ext == '.url' ||
              ext == '.appref-ms') {
            continue;
          }
          entries.add(entity);
        }
      }
    }

    entries.sort(
      (a, b) => path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase()),
    );
    return entries;
  }

  Future<void> _openEntity(FileSystemEntity entity) async {
    await Process.run('explorer.exe', [entity.path]);
  }

  Future<void> _toggleDisplayMode() async {
    final newMode = _displayMode == BoxDisplayMode.grid
        ? BoxDisplayMode.list
        : BoxDisplayMode.grid;
    setState(() => _displayMode = newMode);
    await BoxPrefs().saveDisplayMode(widget.type.name, newMode);
  }

  Future<void> _togglePinned() async {
    final newPinned = !_isPinned;
    setState(() => _isPinned = newPinned);
    await BoxPrefs().savePinned(widget.type.name, newPinned);
  }

  Future<void> _toggleCollapsed() async {
    final newCollapsed = !_isCollapsed;
    _heightAnimator.cancel();

    if (newCollapsed) {
      // Collapsing
      final currentSize = await windowManager.getSize();
      _expandedSize = currentSize;

      setState(() {
        _isCollapsed = true;
        _showContent = _hovering;
      });

      if (!mounted || !_isCollapsed || _hovering) {
        await BoxPrefs().saveCollapsed(widget.type.name, newCollapsed);
        return;
      }

      await Future.delayed(const Duration(milliseconds: 240));
      if (!mounted || _hovering) {
        await BoxPrefs().saveCollapsed(widget.type.name, newCollapsed);
        return;
      }
      await _heightAnimator.jumpTo(50);
    } else {
      // Expanding
      final targetH = _expandedSize?.height ?? 300;
      setState(() {
        _isCollapsed = false;
        _showContent = false;
      });

      await _heightAnimator.jumpTo(targetH);
      await Future.delayed(const Duration(milliseconds: 16));
      if (mounted) setState(() => _showContent = true);
    }

    await BoxPrefs().saveCollapsed(widget.type.name, newCollapsed);
  }

  Future<void> _showMenu() async {
    setState(() => _isMenuOpen = true);
    try {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      final origin = overlay?.localToGlobal(Offset.zero) ?? Offset.zero;
      final result = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(origin.dx + 12, origin.dy + 44, 0, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 8,
        items: [
          PopupMenuItem(
            value: 'refresh',
            padding: EdgeInsets.zero,
            child: _buildMenuItem(Icons.refresh, '刷新'),
          ),
          PopupMenuItem(
            value: 'open_desktop',
            padding: EdgeInsets.zero,
            child: _buildMenuItem(Icons.folder_open, '打开桌面文件夹'),
          ),
          PopupMenuItem(
            value: 'toggle_pin',
            padding: EdgeInsets.zero,
            child: _buildMenuItem(
              _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              _isPinned ? '取消固定' : '固定盒子',
            ),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'close',
            padding: EdgeInsets.zero,
            child: _buildMenuItem(Icons.close, '关闭盒子', isDestructive: true),
          ),
        ],
      );

      switch (result) {
        case 'refresh':
          await _refresh();
          break;
        case 'open_desktop':
          if (_desktopPath.isNotEmpty) {
            await Process.run('explorer.exe', [_desktopPath]);
          }
          break;
        case 'toggle_pin':
          await _togglePinned();
          break;
        case 'close':
          await windowManager.close();
          break;
      }
    } finally {
      if (mounted) setState(() => _isMenuOpen = false);
    }
  }

  Widget _buildMenuItem(
    IconData icon,
    String title, {
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isDestructive
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDestructive
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface.withValues(alpha: 0.9),
              fontFamilyFallback: const ['Microsoft YaHei'],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.type == BoxType.folders ? '文件夹' : '文件和文档';
    final prefs = SharedPrefsHelper();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) async {
          final epoch = ++_hoverTransitionEpoch;
          _heightAnimator.cancel();
          if (mounted) setState(() => _hovering = true);

          // Auto-expand if collapsed (smooth).
          if (!_isCollapsed) return;

          final targetHeight = _expandedSize?.height ?? 300;
          await _heightAnimator.jumpTo(targetHeight);
          if (!mounted || epoch != _hoverTransitionEpoch) return;
          await Future.delayed(const Duration(milliseconds: 16));
          if (!mounted || epoch != _hoverTransitionEpoch) return;
          if (mounted) setState(() => _showContent = true);
        },
        onExit: (_) async {
          final epoch = ++_hoverTransitionEpoch;
          _heightAnimator.cancel();
          if (mounted) setState(() => _hovering = false);

          // Auto-collapse when leaving if in collapsed mode
          if (!_isCollapsed) return;

          // Grace period
          await Future.delayed(const Duration(milliseconds: 160));
          if (!mounted || epoch != _hoverTransitionEpoch) return;

          // Don't collapse if mouse returned OR menu is open OR we are dragging
          if (_hovering || _isMenuOpen || _isDragging) return;

          if (mounted) setState(() => _showContent = false);

          await Future.delayed(const Duration(milliseconds: 240));
          if (!mounted || epoch != _hoverTransitionEpoch) return;
          if (_hovering || _isMenuOpen || _isDragging) return;
          await _heightAnimator.jumpTo(50);
        },
        child: WindowResizeArea(
          child: SafeArea(
            child: Stack(
              clipBehavior: Clip.none, // Allow lines to extend out
              children: [
                RepaintBoundary(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GlassContainer(
                        opacity: prefs.transparency,
                        blurSigma: 18 * prefs.frostStrength,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final contentMaxHeight = math.max(
                              0.0,
                              constraints.maxHeight - _headerHeight,
                            );
                            return Column(
                              children: [
                                BoxHeader(
                                  title: title,
                                  hovering: _hovering,
                                  isPinned: _isPinned,
                                  isCollapsed: _isCollapsed,
                                  displayMode: _displayMode,
                                  onToggleDisplayMode: _toggleDisplayMode,
                                  onToggleCollapsed: _toggleCollapsed,
                                  onMenu: _showMenu,
                                  onRefresh: _refresh,
                                  onClose: () => windowManager.close(),
                                  onDragStart: () {
                                    setState(() => _isDragging = true);
                                    _loadOtherBounds();
                                  },
                                  onDragEnd: () {
                                    if (mounted) {
                                      setState(() => _isDragging = false);
                                    }
                                  },
                                ),
                                BoxContentTransition(
                                  visible: !_isCollapsed || _showContent,
                                  maxHeight: contentMaxHeight,
                                  duration: const Duration(milliseconds: 240),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Divider(height: 1),
                                      Expanded(
                                        child: _loading
                                            ? const Center(
                                                child: CircularProgressIndicator(),
                                              )
                                            : _error != null
                                                ? Center(
                                                    child: Text(
                                                      '加载失败：$_error',
                                                      style: theme.textTheme.bodyMedium,
                                                    ),
                                                  )
                                                : _entries.isEmpty
                                                    ? Center(
                                                        child: Text(
                                                          '暂无内容',
                                                          style: theme.textTheme.bodyMedium
                                                              ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface
                                                                .withValues(alpha: 0.7),
                                                          ),
                                                        ),
                                                      )
                                                    : _displayMode ==
                                                            BoxDisplayMode.grid
                                                        ? BoxGrid(
                                                            entries: _entries,
                                                            type: widget.type,
                                                            onOpen: _openEntity,
                                                          )
                                                        : BoxList(
                                                            entries: _entries,
                                                            type: widget.type,
                                                            onOpen: _openEntity,
                                                          ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                // Alignment Lines - DISABLED
                // TODO: Re-implement using Win32 API for real-time rendering
                // See docs/alignment_lines_issue.md for details
                /*
                if (_alignLeft)
                  Positioned(
                    left: 0,
                    top: -2000,
                    bottom: -2000,
                    width: 2,
                    child: Center(
                      child: Container(width: 2, color: Colors.blueAccent),
                    ),
                  ),
                if (_alignRight)
                  Positioned(
                    right: 0,
                    top: -2000,
                    bottom: -2000,
                    width: 2,
                    child: Center(
                      child: Container(width: 2, color: Colors.blueAccent),
                    ),
                  ),
                if (_alignTop)
                  Positioned(
                    top: 0,
                    left: -2000,
                    right: -2000,
                    height: 2,
                    child: Center(
                      child: Container(height: 2, color: Colors.blueAccent),
                    ),
                  ),
                if (_alignBottom)
                  Positioned(
                    bottom: 0,
                    left: -2000,
                    right: -2000,
                    height: 2,
                    child: Center(
                      child: Container(height: 2, color: Colors.blueAccent),
                    ),
                  ),
                */
              ],
            ),
          ),
        ),
      ),
    );
  }
}

