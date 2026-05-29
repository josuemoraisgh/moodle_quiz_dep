import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// S: Centraliza a definição do tema visual do app.
abstract class AppTheme {
  // ── Paleta principal ──────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0D0D2B);
  static const Color bgCard = Color(0xFF1A1A3E);
  static const Color bgCardAlt = Color(0xFF12122E);
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color accent = Color(0xFF00D4FF);
  static const Color success = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFD600);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B3CC);

  // ── Pódio ─────────────────────────────────────────────────────────────────
  static const Color gold = Color(0xFFFFD700);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);

  // ── Gradientes ────────────────────────────────────────────────────────────
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D0D2B), Color(0xFF1A0533)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
  );

  static const LinearGradient silverGradient = LinearGradient(
    colors: [Color(0xFFE0E0E0), Color(0xFF9E9E9E)],
  );

  static const LinearGradient bronzeGradient = LinearGradient(
    colors: [Color(0xFFCD7F32), Color(0xFF8B4513)],
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: bgCard,
        error: danger,
      ),
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: primary.withValues(alpha: 0.4), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
      ),
    );
  }

  // ── Utilitários de estilo ─────────────────────────────────────────────────
  static TextStyle get headlineLarge => GoogleFonts.nunito(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: textPrimary,
      );

  static TextStyle get headlineMedium => GoogleFonts.nunito(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: textPrimary,
      );

  static TextStyle get scoreText => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: textPrimary,
      );

  static TextStyle get timerText => GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w900,
        color: textPrimary,
      );

  static BoxDecoration cardDecoration({
    Gradient? gradient,
    Color? color,
    double radius = 16,
    bool glowing = false,
  }) {
    return BoxDecoration(
      color: color ?? bgCard,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: glowing
          ? [
              BoxShadow(
                color: primary.withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
    );
  }
}
