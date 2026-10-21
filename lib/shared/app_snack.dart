import 'package:flutter/material.dart';

import '../ui/tokens.dart';

/// Consistent snackbar feedback for the whole app.
///
/// Replaces the per-screen `_showSnack` copies that had drifted into
/// random colors (gold for errors, redAccent for successes). One place
/// owns the styling: success = green, failure = red, neutral = the
/// app's gold. The colors come from the theme so a snackbar reads the
/// same in the light theme.
class AppSnack {
  AppSnack._();

  static void success(BuildContext context, String message) {
    final AppPalette palette = context.palette;
    _show(
      context,
      message,
      palette.success,
      palette.isDark ? AppTokens.darkBg : Colors.white,
    );
  }

  static void error(BuildContext context, String message) {
    final AppPalette palette = context.palette;
    _show(
      context,
      message,
      palette.danger,
      palette.isDark ? AppTokens.darkBg : Colors.white,
    );
  }

  static void info(BuildContext context, String message) {
    final AppPalette palette = context.palette;
    _show(
      context,
      message,
      palette.gold,
      palette.isDark ? AppTokens.darkBg : Colors.white,
    );
  }

  static void _show(
    BuildContext context,
    String message,
    Color background,
    Color foreground,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: foreground, fontWeight: FontWeight.bold),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
