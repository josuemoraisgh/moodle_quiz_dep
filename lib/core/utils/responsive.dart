import 'package:flutter/material.dart';

/// S: Utilitários de layout responsivo.
class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= 600 && w < 1200;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1200;

  /// Retorna valor baseado no tamanho da tela.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  /// Largura máxima para conteúdo centralizado.
  static double contentWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return 900;
    if (w >= 600) return w * 0.85;
    return w;
  }

  /// Padding horizontal responsivo.
  static EdgeInsets horizontalPadding(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return const EdgeInsets.symmetric(horizontal: 48);
    if (w >= 600) return const EdgeInsets.symmetric(horizontal: 32);
    return const EdgeInsets.symmetric(horizontal: 16);
  }
}
