import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../utils/native_helper.dart';

class FileIcon extends StatefulWidget {
  final String path;
  final double size;
  final IconData fallbackIcon;

  const FileIcon({
    super.key,
    required this.path,
    this.size = 32,
    this.fallbackIcon = Icons.insert_drive_file,
  });

  @override
  State<FileIcon> createState() => _FileIconState();
}

class _FileIconState extends State<FileIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(covariant FileIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.size != widget.size) {
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    try {
      final bytes = await extractIconAsync(
        widget.path,
        size: widget.size.toInt(),
      );
      // print('Loaded icon for ${widget.path}: ${bytes?.length} bytes');
      if (mounted) {
        setState(() => _bytes = bytes);
      }
    } catch (e) {
      print('Error loading icon for ${widget.path}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        width: widget.size,
        height: widget.size,
        gaplessPlayback: true,
      );
    }
    return Icon(
      widget.fallbackIcon,
      size: widget.size,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
