import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Extensão de contexto ──────────────────────────────────────────────────────

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

// ── AppColors: paleta dependente do tema ──────────────────────────────────────

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bgSurface;
  final Color bgCard;
  final Color bgCardAlt;
  final Color textPrimary;
  final Color textSecondary;
  final LinearGradient bgGradient;

  const AppColors({
    required this.bgSurface,
    required this.bgCard,
    required this.bgCardAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.bgGradient,
  });

  static const AppColors dark = AppColors(
    bgSurface: Color(0xFF0D0D2B),
    bgCard: Color(0xFF1A1A3E),
    bgCardAlt: Color(0xFF12122E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B3CC),
    bgGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0D0D2B), Color(0xFF1A0533)],
    ),
  );

  static const AppColors light = AppColors(
    bgSurface: Color(0xFFF0F2F8),
    bgCard: Color(0xFFFFFFFF),
    bgCardAlt: Color(0xFFE8EAF4),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF5A5F80),
    bgGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEEF0FA), Color(0xFFE8E0F5)],
    ),
  );

  @override
  AppColors copyWith({
    Color? bgSurface,
    Color? bgCard,
    Color? bgCardAlt,
    Color? textPrimary,
    Color? textSecondary,
    LinearGradient? bgGradient,
  }) {
    return AppColors(
      bgSurface: bgSurface ?? this.bgSurface,
      bgCard: bgCard ?? this.bgCard,
      bgCardAlt: bgCardAlt ?? this.bgCardAlt,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      bgGradient: bgGradient ?? this.bgGradient,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      bgCardAlt: Color.lerp(bgCardAlt, other.bgCardAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      bgGradient: bgGradient,
    );
  }

  BoxDecoration cardDecoration({
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
                color: AppTheme.primary.withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }
}

// ── AppTheme: paleta estática (cores de marca e semânticas) ───────────────────

abstract class AppTheme {
  // ── Alias de retrocompatibilidade (dark palette) ───────────────────────────
  // Prefer context.appColors.* for theme-aware colors.
  static const Color bgDark = Color(0xFF0D0D2B);
  static const Color bgCard = Color(0xFF1A1A3E);
  static const Color bgCardAlt = Color(0xFF12122E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B3CC);
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D0D2B), Color(0xFF1A0533)],
  );

  // ── Cores de marca (iguais em ambos os temas) ─────────────────────────────
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color accent = Color(0xFF00D4FF);
  static const Color success = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFD600);

  // ── Pódio ─────────────────────────────────────────────────────────────────
  static const Color gold = Color(0xFFFFD700);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);

  // ── Gradientes de marca (iguais em ambos os temas) ────────────────────────
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
    final c = AppColors.dark;
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: c.bgSurface,
      extensions: [c],
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: c.bgCard,
        error: danger,
      ),
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: c.bgCard,
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
        fillColor: c.bgCardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: primary.withValues(alpha: 0.4), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: TextStyle(color: c.textSecondary),
        prefixIconColor: c.textSecondary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
        ),
      ),
    );
  }

  static ThemeData get light {
    final c = AppColors.light;
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: c.bgSurface,
      extensions: [c],
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: c.bgCard,
        error: danger,
      ),
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: c.bgCard,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
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
        fillColor: c.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: primary.withValues(alpha: 0.35), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: TextStyle(color: c.textSecondary),
        prefixIconColor: c.textSecondary,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.transparent),
        side: BorderSide(color: c.textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgCard,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: true,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.bgCardAlt,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.bgCard,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: c.textSecondary,
          fontSize: 14,
        ),
      ),
    );
  }

  // ── Utilitário retrocompat (dark only) ───────────────────────────────────
  static BoxDecoration cardDecoration({
    Gradient? gradient,
    Color? color,
    double radius = 16,
    bool glowing = false,
  }) =>
      AppColors.dark.cardDecoration(
        gradient: gradient,
        color: color,
        radius: radius,
        glowing: glowing,
      );

  // ── Utilitários de estilo (cor independente de tema) ──────────────────────

  static TextStyle headlineLarge(BuildContext context) => GoogleFonts.nunito(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: context.appColors.textPrimary,
      );

  static TextStyle headlineMedium(BuildContext context) => GoogleFonts.nunito(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: context.appColors.textPrimary,
      );

  static TextStyle scoreText(BuildContext context) => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: context.appColors.textPrimary,
      );

  static TextStyle timerText(BuildContext context) => GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w900,
        color: context.appColors.textPrimary,
      );
}
