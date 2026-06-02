import 'package:flutter/material.dart';

/// Gerencia o ThemeMode ativo e notifica listeners ao alternar.
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode;

  ThemeNotifier({ThemeMode initialMode = ThemeMode.dark}) : _mode = initialMode;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}
