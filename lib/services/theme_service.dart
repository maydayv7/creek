import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global instance for easy access
final themeService = ThemeService();

class ThemeService with ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('theme_mode');

    if (saved == 'light') {
      _mode = ThemeMode.light;
    } else if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.system;
    }

    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();

    if (_mode == ThemeMode.dark) {
      _mode = ThemeMode.light;
      await prefs.setString('theme_mode', 'light');
    } else {
      _mode = ThemeMode.dark;
      await prefs.setString('theme_mode', 'dark');
    }

    notifyListeners();
  }
}