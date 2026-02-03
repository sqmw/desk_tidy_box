import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../models/box_type.dart';
import 'file_icon.dart';
import 'folder_icon.dart';

class BoxGrid extends StatelessWidget {
  const BoxGrid({
    super.key,
    required this.entries,
    required this.type,
    required this.onOpen,
  });

  final List<FileSystemEntity> entries;
  final BoxType type;
  final Future<void> Function(FileSystemEntity entity) onOpen;

  @override
  Widget build(BuildContext context) {
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
          fallbackIcon: type == BoxType.folders
              ? Icons.folder
              : Icons.insert_drive_file,
        );
      },
    );
  }
}

class _BoxTile extends StatelessWidget {
  const _BoxTile({
    required this.name,
    required this.entity,
    required this.onOpen,
    required this.fallbackIcon,
  });

  final String name;
  final FileSystemEntity entity;
  final Future<void> Function(FileSystemEntity entity) onOpen;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hover = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.25,
    );

    final Widget content = switch (entity) {
      Directory() => FolderIcon(directory: entity as Directory, size: 36),
      _ => FileIcon(path: entity.path, size: 36, fallbackIcon: fallbackIcon),
    };

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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
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

