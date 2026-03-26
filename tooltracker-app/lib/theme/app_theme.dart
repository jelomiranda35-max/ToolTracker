// app_theme.dart — 3-mode theme system
// Modes: 0 = AMTEC (original dark blue/amber), 1 = Light, 2 = Dark (pure dark)

import 'package:flutter/material.dart';

enum AppThemeMode { amtec, light, dark }

class AppColors {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color border;
  final Color borderStrong;
  final Color accent;       // primary amber/brand color
  final Color accentText;   // text on accent
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color headerBg;
  final Color tabBg;
  final Color cardBg;
  final Color inputFill;
  final Color logoRingBg;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.headerBg,
    required this.tabBg,
    required this.cardBg,
    required this.inputFill,
    required this.logoRingBg,
  });
}

// ── AMTEC (original) ─────────────────────────────────────────────────────────
const amtecColors = AppColors(
  background:     Color(0xFF0D1B2A),
  surface:        Color(0xFF1A3A5C),
  surfaceVariant: Color(0xFF111827),
  border:         Color(0xFF1E3A5F),
  borderStrong:   Color(0xFF2A4A6F),
  accent:         Color(0xFFF5A623),
  accentText:     Colors.black,
  textPrimary:    Colors.white,
  textSecondary:  Color(0xB3FFFFFF),   // white70
  textHint:       Color(0x61FFFFFF),   // white38
  headerBg:       Color(0xFF0D1B2A),
  tabBg:          Color(0xFF0D1B2A),
  cardBg:         Color(0xFF1A3A5C),
  inputFill:      Color(0xFF1A3A5C),
  logoRingBg:     Color(0xFF1E3A5F),
);

// ── LIGHT ────────────────────────────────────────────────────────────────────
const lightColors = AppColors(
  background:     Color(0xFFF0F4F8),
  surface:        Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFE8EEF4),
  border:         Color(0xFFCBD5E1),
  borderStrong:   Color(0xFF94A3B8),
  accent:         Color(0xFFD97706),   // amber-600
  accentText:     Colors.white,
  textPrimary:    Color(0xFF0F172A),
  textSecondary:  Color(0xFF475569),
  textHint:       Color(0xFF94A3B8),
  headerBg:       Color(0xFF1E3A5C),  // keep dark header for branding
  tabBg:          Color(0xFFFFFFFF),
  cardBg:         Color(0xFFFFFFFF),
  inputFill:      Color(0xFFFFFFFF),
  logoRingBg:     Color(0xFFE2E8F0),
);

// ── PURE DARK ────────────────────────────────────────────────────────────────
const puredarkColors = AppColors(
  background:     Color(0xFF000000),
  surface:        Color(0xFF121212),
  surfaceVariant: Color(0xFF1C1C1E),
  border:         Color(0xFF2C2C2E),
  borderStrong:   Color(0xFF3A3A3C),
  accent:         Color(0xFFF5A623),
  accentText:     Colors.black,
  textPrimary:    Colors.white,
  textSecondary:  Color(0xB3FFFFFF),
  textHint:       Color(0x61FFFFFF),
  headerBg:       Color(0xFF000000),
  tabBg:          Color(0xFF000000),
  cardBg:         Color(0xFF1C1C1E),
  inputFill:      Color(0xFF1C1C1E),
  logoRingBg:     Color(0xFF2C2C2E),
);

// ── ThemeNotifier ─────────────────────────────────────────────────────────────

class ThemeNotifier extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.amtec;

  AppThemeMode get mode => _mode;

  AppColors get colors {
    switch (_mode) {
      case AppThemeMode.light: return lightColors;
      case AppThemeMode.dark:  return puredarkColors;
      case AppThemeMode.amtec: return amtecColors;
    }
  }

  /// Cycle: amtec → light → dark → amtec
  void nextMode() {
    switch (_mode) {
      case AppThemeMode.amtec: _mode = AppThemeMode.light; break;
      case AppThemeMode.light: _mode = AppThemeMode.dark;  break;
      case AppThemeMode.dark:  _mode = AppThemeMode.amtec; break;
    }
    notifyListeners();
  }

  String get modeName {
    switch (_mode) {
      case AppThemeMode.amtec: return 'AMTEC';
      case AppThemeMode.light: return 'Light';
      case AppThemeMode.dark:  return 'Dark';
    }
  }
}
