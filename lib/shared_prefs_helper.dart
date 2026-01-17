import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class SharedPrefsHelper {
  static const _kTransparency = 'ui.transparency';
  static const _kFrostStrength = 'ui.frostStrength';
  static const _kThemeMode = 'ui.themeMode';
  static const _kBeautifyStyle = 'ui.beautify.style';
  static const _kIconSize = 'ui.iconSize';

  // Singleton
  static final SharedPrefsHelper _instance = SharedPrefsHelper._();
  factory SharedPrefsHelper() => _instance;
  SharedPrefsHelper._();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Reload prefs in case main app changed them
  Future<void> reload() async {
    await _prefs.reload();
  }

  double get transparency => _prefs.getDouble(_kTransparency) ?? 0.2;
  double get frostStrength => _prefs.getDouble(_kFrostStrength) ?? 0.82;
  double get iconSize => _prefs.getDouble(_kIconSize) ?? 32.0;

  ThemeMode get themeMode {
    final idx = _prefs.getInt(_kThemeMode);
    if (idx == null) return ThemeMode.dark;
    // Map index to ThemeMode. Assumes standard index order: 0=system, 1=light, 2=dark
    // But desk_tidy might use a custom enum. Checking AppPreferences:
    // ThemeModeOption.system, light, dark.
    // If desk_tidy uses indexes 0, 1, 2, then:
    switch (idx) {
      case 0:
        return ThemeMode.system;
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  // Helper for alignment guide threshold (internal config, not shared, but good to have here?)
  // No, keep local configs local.
}
