import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the light and dark themes from [AppTokens].
///
/// Everything visual — surfaces, borders, typography, controls — is
/// defined here so screens only compose layout. Switching themes is a
/// `themeMode` change; no screen re-implements its own colours.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(AppPalette.light);

  static ThemeData get dark => _build(AppPalette.dark);

  static ThemeData _build(AppPalette palette) {
    final Brightness brightness = palette.isDark
        ? Brightness.dark
        : Brightness.light;
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppTokens.gold,
          brightness: brightness,
        ).copyWith(
          primary: palette.gold,
          onPrimary: palette.isDark ? AppTokens.darkBg : Colors.white,
          secondary: palette.gold,
          onSecondary: palette.isDark ? AppTokens.darkBg : Colors.white,
          surface: palette.surface,
          onSurface: palette.text,
          surfaceContainerHighest: palette.surfaceAlt,
          outline: palette.border,
          outlineVariant: palette.border,
          error: palette.danger,
          onError: Colors.white,
        );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final TextTheme text = base.textTheme
        .apply(bodyColor: palette.text, displayColor: palette.text)
        .copyWith(
          displaySmall: base.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        );

    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      borderSide: BorderSide(color: palette.border),
    );

    return base.copyWith(
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.surface,
      dividerColor: palette.border,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: palette.text),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1),
      iconTheme: IconThemeData(color: palette.muted),
      listTileTheme: ListTileThemeData(
        iconColor: palette.muted,
        textColor: palette.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: TextStyle(color: palette.muted),
        labelStyle: TextStyle(color: palette.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.gold, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.danger, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.gold,
          foregroundColor: palette.isDark ? AppTokens.darkBg : Colors.white,
          disabledBackgroundColor: palette.surfaceAlt,
          disabledForegroundColor: palette.muted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.gold,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.gold.withValues(alpha: 0.16),
        disabledColor: palette.surfaceAlt,
        labelStyle: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(color: palette.gold),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.gold.withValues(alpha: 0.18),
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? palette.gold : palette.muted,
            size: 23,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.gold.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: palette.gold),
        unselectedIconTheme: IconThemeData(color: palette.muted),
        selectedLabelTextStyle: TextStyle(
          color: palette.gold,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: palette.muted,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.isDark
            ? AppTokens.darkSurfaceAlt
            : AppTokens.lightText,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: palette.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.gold,
        linearTrackColor: palette.surfaceAlt,
        circularTrackColor: palette.surfaceAlt,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.isDark ? palette.surfaceAlt : AppTokens.lightText,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
