import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../models/box_type.dart';
import 'file_icon.dart';
import 'folder_icon.dart';

class BoxList extends StatefulWidget {
  const BoxList({
    super.key,
    required this.entries,
    required this.type,
    required this.onOpen,
  });

  final List<FileSystemEntity> entries;
  final BoxType type;
  final Future<void> Function(FileSystemEntity entity) onOpen;

  @override
  State<BoxList> createState() => _BoxListState();
}

class _BoxListState extends State<BoxList> {
  static const double _handleZoneWidth = 24.0;
  static const double _sidePadding = 16.0;

  double _nameWidth = 250;
  double _dateWidth = 140;
  double _typeWidth = 80;
  double _sizeWidth = 80;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fixedColumnsWidth = _dateWidth + _typeWidth + _sizeWidth;
        final totalDecorationWidth = (_sidePadding * 2) + (_handleZoneWidth * 3);
        final totalWidth = _nameWidth + fixedColumnsWidth + totalDecorationWidth;

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
                      handleWidth: _handleZoneWidth,
                      sidePadding: _sidePadding,
                      onResizeName: (dx) => setState(
                        () => _nameWidth = (_nameWidth + dx).clamp(100.0, 500.0),
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
                        padding: EdgeInsets.zero,
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
                            handleWidth: _handleZoneWidth,
                            sidePadding: _sidePadding,
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
          SizedBox(width: nameWidth, child: Text('名称', style: style)),
          _ResizeHandle(width: handleWidth, onDrag: onResizeName),
          SizedBox(width: dateWidth, child: Text('修改日期', style: style)),
          _ResizeHandle(width: handleWidth, onDrag: onResizeDate),
          SizedBox(width: typeWidth, child: Text('类型', style: style)),
          _ResizeHandle(width: handleWidth, onDrag: onResizeType),
          SizedBox(width: sizeWidth, child: Text('大小', style: style)),
        ],
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.width, required this.onDrag});

  final double width;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
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

  final FileSystemEntity entity;
  final BoxType type;
  final Future<void> Function(FileSystemEntity entity) onOpen;

  final double nameWidth;
  final double dateWidth;
  final double typeWidth;
  final double sizeWidth;
  final double handleWidth;
  final double sidePadding;

  String _formatDate(DateTime date) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 0) return '';
    if (bytes == 0) return '0 KB';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    if (i == 0) return '${size.round()} ${suffixes[i]}';
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[i]}';
  }

  String _getType(FileSystemEntity entity) {
    if (entity is Directory) return '文件夹';
    final ext = path.extension(entity.path).toLowerCase();
    if (ext.isEmpty) return '文件';
    return '${ext.substring(1).toUpperCase()} 文件';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = path.basename(entity.path);

    FileStat? stat;
    try {
      stat = entity.statSync();
    } catch (_) {}

    final dateStr = stat != null ? _formatDate(stat.modified) : '';
    final sizeStr = (entity is File && stat != null) ? _formatSize(stat.size) : '';
    final typeStr = _getType(entity);

    final Widget iconWidget = switch (entity) {
      Directory() => FolderIcon(directory: entity as Directory, size: 24),
      _ => FileIcon(
          path: entity.path,
          size: 24,
          fallbackIcon: type == BoxType.folders
              ? Icons.folder
              : Icons.insert_drive_file,
        ),
    };

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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: handleWidth),
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

