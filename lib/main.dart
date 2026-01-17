import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'box_page.dart';
import 'box_prefs.dart';
import 'shared_prefs_helper.dart';

/// Box types
enum BoxType { folders, files }

/// Command-line arguments for the box
class BoxArgs {
  final BoxType type;
  final String desktopPath;
  final int parentPid;

  const BoxArgs({
    required this.type,
    required this.desktopPath,
    required this.parentPid,
  });

  static BoxArgs parse(List<String> args) {
    BoxType type = BoxType.folders;
    String desktopPath = '';
    int parentPid = 0;

    for (final arg in args) {
      if (arg.startsWith('--type=')) {
        final val = arg.substring('--type='.length);
        type = val == 'files' ? BoxType.files : BoxType.folders;
      } else if (arg.startsWith('--desktop-path=')) {
        desktopPath = arg.substring('--desktop-path='.length);
      } else if (arg.startsWith('--parent-pid=')) {
        parentPid = int.tryParse(arg.substring('--parent-pid='.length)) ?? 0;
      }
    }

    return BoxArgs(type: type, desktopPath: desktopPath, parentPid: parentPid);
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final boxArgs = BoxArgs.parse(args);
  final title = boxArgs.type == BoxType.folders ? '文件夹' : '文件和文档';

  // Restore window bounds if available
  final prefs = BoxPrefs();
  final sharedPrefs = SharedPrefsHelper();
  await sharedPrefs.init();

  BoxBounds? bounds = await prefs.loadBounds(boxArgs.type.name);

  // Calculate default position if no saved bounds
  if (bounds == null) {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final screenW = display.visibleSize?.width ?? display.size.width;
      // Using visibleSize to account for taskbar if possible, otherwise size.
      // screen_retriever Display has .size and .visibleSize

      const double w = 320;
      const double h = 280;
      final double x = screenW - w - 20; // 20px padding from right

      final double y = boxArgs.type == BoxType.folders ? 100 : 100 + h + 20;

      // Save these bounds so we can use them in waitUntilReadyToShow
      bounds = BoxBounds(
        x: x.round(),
        y: y.round(),
        width: w.round(),
        height: h.round(),
      );
    } catch (_) {
      // Fallback if screen retriever fails
    }
  }

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      title: title,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      size: bounds != null
          ? Size(bounds.width.toDouble(), bounds.height.toDouble())
          : const Size(320, 280),
    ),
    () async {
      await windowManager.setAsFrameless();
      // Enable resizing but disable maximize
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(false);
      await windowManager.setMinimizable(true);
      // Prevent Windows Aero Snap when dragging
      await windowManager.setPreventClose(false);
      if (bounds != null) {
        await windowManager.setPosition(
          Offset(bounds.x.toDouble(), bounds.y.toDouble()),
        );
      }
      await windowManager.show();
    },
  );

  runApp(BoxApp(args: boxArgs));
}

class BoxApp extends StatefulWidget {
  final BoxArgs args;

  const BoxApp({super.key, required this.args});

  @override
  State<BoxApp> createState() => _BoxAppState();
}

class _BoxAppState extends State<BoxApp> with WindowListener {
  final BoxPrefs _prefs = BoxPrefs();
  Timer? _parentWatch;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _startParentWatch();
  }

  @override
  void dispose() {
    _parentWatch?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _startParentWatch() {
    final parentPid = widget.args.parentPid;
    if (parentPid <= 0) return;

    _parentWatch?.cancel();
    _parentWatch = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isProcessRunning(parentPid)) {
        try {
          await windowManager.close();
        } finally {
          exit(0);
        }
      }
    });
  }

  bool _isProcessRunning(int pid) {
    if (!Platform.isWindows) return false;
    try {
      final result = Process.runSync('tasklist', ['/FI', 'PID eq $pid']);
      return result.stdout.toString().contains('$pid');
    } catch (_) {
      return false;
    }
  }

  Timer? _saveTimer;

  Future<void> _saveBounds() async {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () async {
      final rect = await windowManager.getBounds();
      await _prefs.saveBounds(
        widget.args.type.name,
        BoxBounds(
          x: rect.left.round(),
          y: rect.top.round(),
          width: rect.width.round(),
          height: rect.height.round(),
        ),
      );
    });
  }

  @override
  void onWindowMoved() => _saveBounds();

  @override
  void onWindowResized() => _saveBounds();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.args.type == BoxType.folders ? '文件夹' : '文件和文档',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
      ),
      home: BoxPage(
        type: widget.args.type,
        desktopPath: widget.args.desktopPath,
      ),
    );
  }
}
