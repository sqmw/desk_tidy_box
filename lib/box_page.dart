import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

import 'main.dart';
import 'glass_container.dart';

class BoxPage extends StatefulWidget {
  final BoxType type;
  final String desktopPath;

  const BoxPage({super.key, required this.type, required this.desktopPath});

  @override
  State<BoxPage> createState() => _BoxPageState();
}

class _BoxPageState extends State<BoxPage> {
  bool _hovering = false;
  bool _loading = true;
  String? _error;
  List<FileSystemEntity> _entries = const [];
  String _desktopPath = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final desktopPath = widget.desktopPath.isNotEmpty
        ? widget.desktopPath
        : await _getDesktopPath();
    if (!mounted) return;
    setState(() => _desktopPath = desktopPath);
    await _refresh();
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

  Future<void> _showMenu() async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final origin = overlay?.localToGlobal(Offset.zero) ?? Offset.zero;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx + 12, origin.dy + 44, 0, 0),
      items: const [
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
      case 'close':
        await windowManager.close();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.type == BoxType.folders ? '文件夹' : '文件和文档';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GlassContainer(
            opacity: 0.22,
            blurSigma: 18,
            child: Column(
              children: [
                _BoxHeader(
                  title: title,
                  hovering: _hovering,
                  onMenu: _showMenu,
                  onRefresh: _refresh,
                  onClose: () => windowManager.close(),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        )
                      : _BoxGrid(
                          entries: _entries,
                          type: widget.type,
                          onOpen: _openEntity,
                        ),
                ),
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
  final VoidCallback onMenu;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  const _BoxHeader({
    required this.title,
    required this.hovering,
    required this.onMenu,
    required this.onRefresh,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
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
              Icon(
                icon,
                size: 36,
                color: icon == Icons.folder
                    ? Colors.amber
                    : theme.colorScheme.primary,
              ),
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
