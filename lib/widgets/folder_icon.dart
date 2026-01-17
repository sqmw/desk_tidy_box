import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:desk_tidy_box/utils/native_helper.dart';

class FolderIcon extends StatefulWidget {
  final Directory directory;
  final double size;

  const FolderIcon({super.key, required this.directory, this.size = 48});

  @override
  State<FolderIcon> createState() => _FolderIconState();
}

class _FolderIconState extends State<FolderIcon> {
  Uint8List? _iconBytes;

  @override
  void initState() {
    super.initState();
    _loadNativeIcon();
  }

  @override
  void didUpdateWidget(covariant FolderIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory.path != widget.directory.path) {
      _loadNativeIcon();
    }
  }

  Future<void> _loadNativeIcon() async {
    if (!mounted) return;
    // Standard icon extraction
    final bytes = await extractIconAsync(widget.directory.path, size: 256);

    if (mounted) {
      setState(() {
        _iconBytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If native icon loaded, show it (it includes the folder image + content if available)
    if (_iconBytes != null) {
      return Image.memory(
        _iconBytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    // Standard folder icon fallback if native extraction fails
    return Icon(Icons.folder, size: widget.size, color: Colors.amber[600]);
  }
}
