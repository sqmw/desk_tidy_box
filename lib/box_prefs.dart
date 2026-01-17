import 'package:shared_preferences/shared_preferences.dart';

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
}
