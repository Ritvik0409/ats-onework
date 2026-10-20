import 'package:flutter/material.dart';

/// The single source of truth for colour, shape and spacing.
///
/// Screens must not hard-code colours: ask [AppPalette.of] for the
/// active theme instead. The palette keeps the app's gold identity while
/// giving the light theme its own warm paper-like surfaces.
class AppTokens {
  const AppTokens._();

  // Brand
  static const Color gold = Color(0xFFE2B93B);
  static const Color goldDeep = Color(0xFFB8891B);
  static const Color goldSoft = Color(0xFFF3E5AB);

  // Dark surfaces
  static const Color darkBg = Color(0xFF0B0B10);
  static const Color darkSurface = Color(0xFF14141C);
  static const Color darkSurfaceAlt = Color(0xFF1C1C27);
  static const Color darkBorder = Color(0xFF2A2A38);
  static const Color darkText = Color(0xFFF4F4F7);
  static const Color darkMuted = Color(0xFF9AA0AE);

  // Light surfaces
  static const Color lightBg = Color(0xFFF6F4EE);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF0EEE7);
  static const Color lightBorder = Color(0xFFE3DFD4);
  static const Color lightText = Color(0xFF1B1B22);
  static const Color lightMuted = Color(0xFF6C6F7A);

  // Semantic
  static const Color success = Color(0xFF2FA36B);
  static const Color successBright = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFD9820F);
  static const Color warningBright = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFD1453B);
  static const Color dangerBright = Color(0xFFF87171);
  static const Color info = Color(0xFF3B6FD4);
  static const Color infoBright = Color(0xFF60A5FA);

  /// Categorical chart colours. Chosen to stay distinguishable on both
  /// the dark and the light surface.
  static const List<Color> chart = <Color>[
    Color(0xFFE2B93B),
    Color(0xFF5B8DEF),
    Color(0xFF34C77B),
    Color(0xFFE07A5F),
    Color(0xFF9B7EDE),
    Color(0xFF4CC9C0),
    Color(0xFFF2A65A),
    Color(0xFF8A94A6),
  ];

  // Shape + spacing
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double gapXs = 6;
  static const double gapSm = 12;
  static const double gapMd = 18;
  static const double gapLg = 28;
  static const double pageMaxWidth = 1180;
}

/// Theme-aware palette. One instance per brightness, resolved from the
/// active [Theme].
class AppPalette {
  const AppPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.gold,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.chart,
    required this.shadow,
  });

  final bool isDark;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color gold;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final List<Color> chart;
  final List<BoxShadow> shadow;

  static const AppPalette dark = AppPalette(
    isDark: true,
    bg: AppTokens.darkBg,
    surface: AppTokens.darkSurface,
    surfaceAlt: AppTokens.darkSurfaceAlt,
    border: AppTokens.darkBorder,
    text: AppTokens.darkText,
    muted: AppTokens.darkMuted,
    gold: AppTokens.gold,
    success: AppTokens.successBright,
    warning: AppTokens.warningBright,
    danger: AppTokens.dangerBright,
    info: AppTokens.infoBright,
    chart: AppTokens.chart,
    shadow: <BoxShadow>[],
  );

  static const AppPalette light = AppPalette(
    isDark: false,
    bg: AppTokens.lightBg,
    surface: AppTokens.lightSurface,
    surfaceAlt: AppTokens.lightSurfaceAlt,
    border: AppTokens.lightBorder,
    text: AppTokens.lightText,
    muted: AppTokens.lightMuted,
    gold: AppTokens.goldDeep,
    success: AppTokens.success,
    warning: AppTokens.warning,
    danger: AppTokens.danger,
    info: AppTokens.info,
    chart: AppTokens.chart,
    shadow: <BoxShadow>[
      BoxShadow(color: Color(0x0F1B1B22), blurRadius: 18, offset: Offset(0, 6)),
      BoxShadow(color: Color(0x081B1B22), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color chartColor(int index) => chart[index % chart.length];

  Color tint(Color color, [double alpha = 0.12]) =>
      color.withValues(alpha: alpha);
}

/// Shortcut for the active palette.
extension PaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}
