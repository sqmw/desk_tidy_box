import 'package:shared_preferences/shared_preferences.dart';

enum BoxDisplayMode { grid, list }

class BoxBounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const BoxBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class BoxPrefs {
  static const String _prefix = 'box.window.';
  static const String _displayModePrefix = 'box.';

  Future<BoxBounds?> loadBounds(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getInt('$_prefix$key.x');
    final y = prefs.getInt('$_prefix$key.y');
    final w = prefs.getInt('$_prefix$key.w');
    final h = prefs.getInt('$_prefix$key.h');
    if (x == null || y == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return BoxBounds(x: x, y: y, width: w, height: h);
  }

  Future<void> saveBounds(String key, BoxBounds bounds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$key.x', bounds.x);
    await prefs.setInt('$_prefix$key.y', bounds.y);
    await prefs.setInt('$_prefix$key.w', bounds.width);
    await prefs.setInt('$_prefix$key.h', bounds.height);
  }

  /// Mark a box as running or stopped
  Future<void> saveRunning(String key, bool running) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key.running', running);
  }

  /// Check if a box is currently running
  Future<bool> loadRunning(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$key.running') ?? false;
  }

  Future<BoxDisplayMode> loadDisplayMode(String boxType) async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('$_displayModePrefix$boxType.displayMode');
    if (index == null) return BoxDisplayMode.grid; // Default
    return BoxDisplayMode.values[index.clamp(
      0,
      BoxDisplayMode.values.length - 1,
    )];
  }

  Future<void> saveDisplayMode(String boxType, BoxDisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_displayModePrefix$boxType.displayMode', mode.index);
  }

  Future<bool> loadPinned(String boxType) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_displayModePrefix$boxType.pinned') ?? false;
  }

  Future<void> savePinned(String boxType, bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_displayModePrefix$boxType.pinned', pinned);
  }

  Future<bool> loadCollapsed(String boxType) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_displayModePrefix$boxType.collapsed') ?? false;
  }

  Future<void> saveCollapsed(String boxType, bool collapsed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_displayModePrefix$boxType.collapsed', collapsed);
  }
}
