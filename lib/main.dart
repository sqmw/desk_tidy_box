import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'box_page.dart';
import 'box_prefs.dart';

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
  final bounds = await prefs.loadBounds(boxArgs.type.name);

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

  Future<void> _saveBounds() async {
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
