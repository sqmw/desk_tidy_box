import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

import 'main.dart';
import 'glass_container.dart';
import 'widgets/folder_icon.dart';
import 'widgets/window_resize_area.dart';
import 'shared_prefs_helper.dart';
import 'box_prefs.dart';

class BoxPage extends StatefulWidget {
  final BoxType type;
  final String desktopPath;

  const BoxPage({super.key, required this.type, required this.desktopPath});

  @override
  State<BoxPage> createState() => _BoxPageState();
}

class _BoxPageState extends State<BoxPage> with WindowListener {
  bool _hovering = false;
  bool _loading = true;
  String? _error;
  List<FileSystemEntity> _entries = const [];
  String _desktopPath = '';

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

  @override
  void initState() {
    super.initState();
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

    if (newCollapsed) {
      // Collapsing
      final currentSize = await windowManager.getSize();
      _expandedSize = currentSize;

      setState(() {
        _isCollapsed = true;
        _showContent = false;
      });

      // Visual shrink animation (handled by AnimatedContainer in build)
      await Future.delayed(const Duration(milliseconds: 150));

      // Physically shrink window only AFTER visual animation
      if (mounted && _isCollapsed && !_hovering) {
        await windowManager.setSize(Size(currentSize.width, 50));
      }
    } else {
      // Expanding
      final targetH = _expandedSize?.height ?? 300;
      final curSize = await windowManager.getSize();

      // 1. Physically expand window INSTANTLY (User said this was good)
      await windowManager.setSize(Size(curSize.width, targetH));

      setState(() {
        _isCollapsed = false;
      });

      // 2. Wait for layout, then show content
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        setState(() => _showContent = true);
      }
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
        items: [
          PopupMenuItem(
            value: 'refresh',
            child: ListTile(leading: Icon(Icons.refresh), title: Text('刷新')),
          ),
          PopupMenuItem(
            value: 'open_desktop',
            child: ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('打开桌面文件夹'),
            ),
          ),
          PopupMenuItem(
            value: 'toggle_pin',
            child: ListTile(
              leading: Icon(
                _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(_isPinned ? '取消固定' : '固定盒子'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'close',
            child: ListTile(leading: Icon(Icons.close), title: Text('关闭盒子')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.type == BoxType.folders ? '文件夹' : '文件和文档';
    final prefs = SharedPrefsHelper();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) async {
          if (mounted) setState(() => _hovering = true);
          // Auto-expand FIRST if collapsed
          if (_isCollapsed) {
            final targetHeight = _expandedSize?.height ?? 300;
            final curSize = await windowManager.getSize();
            // Instant resize expansion as it was "good"
            await windowManager.setSize(Size(curSize.width, targetHeight));

            await Future.delayed(const Duration(milliseconds: 50));
            if (mounted && _hovering) {
              setState(() => _showContent = true);
            }
          }
        },
        onExit: (_) async {
          if (mounted) setState(() => _hovering = false);

          // Auto-collapse when leaving if in collapsed mode
          if (_isCollapsed) {
            // Grace period
            await Future.delayed(const Duration(milliseconds: 200));

            // Don't collapse if mouse returned OR menu is open OR we are dragging
            if (_hovering || _isMenuOpen || _isDragging) return;

            if (mounted) setState(() => _showContent = false);

            // Give visual hide and container shrink animation time (150ms)
            await Future.delayed(const Duration(milliseconds: 150));

            // Re-check before physical resize
            if (_hovering || _isMenuOpen || _isDragging) return;

            if (mounted) {
              final curSize = await windowManager.getSize();
              await windowManager.setSize(Size(curSize.width, 50));
            }
          }
        },
        child: WindowResizeArea(
          child: SafeArea(
            child: Stack(
              clipBehavior: Clip.none, // Allow lines to extend out
              children: [
                RepaintBoundary(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.fastOutSlowIn,
                    // Use expanded height or default when showContent is true
                    height: _showContent ? null : 50.0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GlassContainer(
                        opacity: prefs.transparency,
                        blurSigma: 18 * prefs.frostStrength,
                        child: Column(
                          children: [
                            _BoxHeader(
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
                              onDragStart: () async {
                                setState(() => _isDragging = true);
                                // If dragging a collapsed box, expand it immediately
                                if (_isCollapsed) {
                                  final targetHeight =
                                      _expandedSize?.height ?? 300;
                                  final curSize = await windowManager.getSize();
                                  await windowManager.setSize(
                                    Size(curSize.width, targetHeight),
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _isCollapsed = false;
                                      _showContent = true;
                                    });
                                  }
                                }
                                _loadOtherBounds();
                              },
                              onDragEnd: () {
                                if (mounted)
                                  setState(() => _isDragging = false);
                              },
                            ),
                            // We keep the widget in the tree to allow AnimatedAlign to work.
                            // It only shows if _isCollapsed is false OR _showContent is true.
                            if (!_isCollapsed || _showContent || _hovering)
                              Expanded(
                                child: ClipRect(
                                  child: AnimatedAlign(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    heightFactor: _showContent ? 1.0 : 0.0,
                                    child:
                                        Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                const Divider(height: 1),
                                                Expanded(
                                                  child: _loading
                                                      ? const Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        )
                                                      : _error != null
                                                      ? Center(
                                                          child: Text(
                                                            '加载失败：$_error',
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium,
                                                          ),
                                                        )
                                                      : _entries.isEmpty
                                                      ? Center(
                                                          child: Text(
                                                            '暂无内容',
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                  color: theme
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withValues(
                                                                        alpha:
                                                                            0.7,
                                                                      ),
                                                                ),
                                                          ),
                                                        )
                                                      : _displayMode ==
                                                            BoxDisplayMode.grid
                                                      ? _BoxGrid(
                                                          entries: _entries,
                                                          type: widget.type,
                                                          onOpen: _openEntity,
                                                        )
                                                      : _BoxList(
                                                          entries: _entries,
                                                          type: widget.type,
                                                          onOpen: _openEntity,
                                                        ),
                                                ),
                                              ],
                                            )
                                            .animate(
                                              target: _showContent ? 1 : 0,
                                            )
                                            .fadeIn(
                                              duration: 300.ms,
                                              curve: Curves.easeIn,
                                            )
                                            .slideY(
                                              begin: -0.05,
                                              end: 0,
                                              duration: 400.ms,
                                              curve: Curves.easeOutCubic,
                                            )
                                            .scaleXY(
                                              begin: 0.98,
                                              end: 1.0,
                                              duration: 400.ms,
                                              curve: Curves.easeOutCubic,
                                            ),
                                  ),
                                ),
                              ),
                          ],
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

class _BoxHeader extends StatelessWidget {
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

  const _BoxHeader({
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

  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: GestureDetector(
        // To allow dragging the window by the header
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          if (isPinned) return; // Don't allow dragging if pinned
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
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: hovering ? 1 : 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isCollapsed ? '展开盒子' : '收起盒子',
                    onPressed: onToggleCollapsed,
                    icon: Icon(
                      isCollapsed ? Icons.expand_less : Icons.expand_more,
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
                    icon: const Icon(Icons.menu),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _BoxGrid extends StatelessWidget {
  final List<FileSystemEntity> entries;
  final BoxType type;
  final Future<void> Function(FileSystemEntity entity) onOpen;

  const _BoxGrid({
    required this.entries,
    required this.type,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 70,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.75,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entity = entries[index];
        final name = path.basename(entity.path);
        return _BoxTile(
          name: name,
          entity: entity,
          onOpen: onOpen,
          icon: type == BoxType.folders
              ? Icons.folder
              : Icons.insert_drive_file,
          theme: theme,
        );
      },
    );
  }
}

class _BoxList extends StatefulWidget {
  final List<FileSystemEntity> entries;
  final BoxType type;
  final Future<void> Function(FileSystemEntity entity) onOpen;

  const _BoxList({
    super.key,
    required this.entries,
    required this.type,
    required this.onOpen,
  });

  @override
  State<_BoxList> createState() => _BoxListState();
}

class _BoxListState extends State<_BoxList> {
  // Layout Constants
  static const double kHandleZoneWidth = 24.0;
  static const double kSidePadding = 16.0;

  // Initial widths for columns
  double _nameWidth = 250;
  double _dateWidth = 140;
  double _typeWidth = 80;
  double _sizeWidth = 80;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Precise calculation of fixed width elements:
        // 1. Column widths for Date, Type, Size
        // 2. 3 Resize handles (each 24px)
        // 3. Side paddings (16px left, 16px right)
        final fixedColumnsWidth = _dateWidth + _typeWidth + _sizeWidth;
        final totalDecorationWidth =
            (kSidePadding * 2) + (kHandleZoneWidth * 3);
        final totalWidth =
            _nameWidth + fixedColumnsWidth + totalDecorationWidth;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    _BoxListHeader(
                      nameWidth: _nameWidth,
                      dateWidth: _dateWidth,
                      typeWidth: _typeWidth,
                      sizeWidth: _sizeWidth,
                      handleWidth: kHandleZoneWidth,
                      sidePadding: kSidePadding,
                      onResizeName: (dx) => setState(
                        () =>
                            _nameWidth = (_nameWidth + dx).clamp(100.0, 500.0),
                      ),
                      onResizeDate: (dx) => setState(
                        () => _dateWidth = (_dateWidth + dx).clamp(80.0, 300.0),
                      ),
                      onResizeType: (dx) => setState(
                        () => _typeWidth = (_typeWidth + dx).clamp(50.0, 200.0),
                      ),
                      onResizeSize: (dx) => setState(
                        () => _sizeWidth = (_sizeWidth + dx).clamp(50.0, 200.0),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero, // Padding handled by items
                        itemCount: widget.entries.length,
                        itemBuilder: (context, index) {
                          final entity = widget.entries[index];
                          return _BoxListItem(
                            entity: entity,
                            type: widget.type,
                            onOpen: widget.onOpen,
                            nameWidth: _nameWidth,
                            dateWidth: _dateWidth,
                            typeWidth: _typeWidth,
                            sizeWidth: _sizeWidth,
                            handleWidth: kHandleZoneWidth,
                            sidePadding: kSidePadding,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoxListHeader extends StatelessWidget {
  final double nameWidth;
  final double dateWidth;
  final double typeWidth;
  final double sizeWidth;
  final double handleWidth;
  final double sidePadding;
  final ValueChanged<double> onResizeName;
  final ValueChanged<double> onResizeDate;
  final ValueChanged<double> onResizeType;
  final ValueChanged<double> onResizeSize;

  const _BoxListHeader({
    required this.nameWidth,
    required this.dateWidth,
    required this.typeWidth,
    required this.sizeWidth,
    required this.handleWidth,
    required this.sidePadding,
    required this.onResizeName,
    required this.onResizeDate,
    required this.onResizeType,
    required this.onResizeSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(sidePadding, 12, sidePadding, 12),
      child: Row(
        children: [
          SizedBox(
            width: nameWidth,
            child: Text('名称', style: style),
          ),
          _ResizeHandle(width: handleWidth, onDrag: onResizeName),
          SizedBox(
            width: dateWidth,
            child: Text('修改日期', style: style),
          ),
          _ResizeHandle(width: handleWidth, onDrag: onResizeDate),
          SizedBox(
            width: typeWidth,
            child: Text('类型', style: style),
          ),
          _ResizeHandle(width: handleWidth, onDrag: onResizeType),
          SizedBox(
            width: sizeWidth,
            child: Text('大小', style: style),
          ),
        ],
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final double width;
  final Function(double dx) onDrag;

  const _ResizeHandle({required this.width, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          onDrag(details.delta.dx);
        },
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(
              width: 1,
              height: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoxListItem extends StatelessWidget {
  final FileSystemEntity entity;
  final BoxType type;
  final Future<void> Function(FileSystemEntity entity) onOpen;

  final double nameWidth;
  final double dateWidth;
  final double typeWidth;
  final double sizeWidth;
  final double handleWidth;
  final double sidePadding;

  const _BoxListItem({
    required this.entity,
    required this.type,
    required this.onOpen,
    required this.nameWidth,
    required this.dateWidth,
    required this.typeWidth,
    required this.sizeWidth,
    required this.handleWidth,
    required this.sidePadding,
  });

  String _formatDate(DateTime date) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[i]}';
  }

  String _getType(FileSystemEntity entity) {
    if (entity is Directory) return '文件夹';
    final ext = path.extension(entity.path).toLowerCase();
    if (ext.isEmpty) return '文件';
    return ext.substring(1).toUpperCase() + ' 文件';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = path.basename(entity.path);

    // Get file stats
    FileStat? stat;
    try {
      stat = entity.statSync();
    } catch (_) {}

    final dateStr = stat != null ? _formatDate(stat.modified) : '';
    final sizeStr = (entity is File && stat != null)
        ? _formatSize(stat.size)
        : '';
    final typeStr = _getType(entity);

    Widget iconWidget;
    if (entity is Directory) {
      iconWidget = FolderIcon(directory: entity as Directory, size: 24);
    } else {
      iconWidget = Icon(
        type == BoxType.folders ? Icons.folder : Icons.insert_drive_file,
        size: 24,
        color: type == BoxType.folders
            ? Colors.amber
            : theme.colorScheme.primary,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onDoubleTap: () => onOpen(entity),
        hoverColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.2,
        ),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 8),
          child: Row(
            children: [
              // Name Column - Explicit width
              SizedBox(
                width: nameWidth,
                child: Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Match Header's ResizeHandle width
              SizedBox(width: handleWidth),

              // Date Column
              SizedBox(
                width: dateWidth,
                child: Text(
                  dateStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: handleWidth),

              // Type Column
              SizedBox(
                width: typeWidth,
                child: Text(
                  typeStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: handleWidth),

              // Size Column
              SizedBox(
                width: sizeWidth,
                child: Text(
                  sizeStr,
                  textAlign: TextAlign.left,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxTile extends StatelessWidget {
  final String name;
  final FileSystemEntity entity;
  final Future<void> Function(FileSystemEntity entity) onOpen;
  final IconData icon;
  final ThemeData theme;

  const _BoxTile({
    required this.name,
    required this.entity,
    required this.onOpen,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final hover = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.25,
    );

    // Determine content widget
    Widget content;
    if (entity is Directory) {
      content = FolderIcon(directory: entity as Directory, size: 36);
    } else {
      content = Icon(
        icon,
        size: 36,
        color: icon == Icons.folder ? Colors.amber : theme.colorScheme.primary,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: hover,
        onDoubleTap: () => onOpen(entity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              content,
              const SizedBox(height: 4),
              Flexible(
                child: Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.85,
                      ),
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
