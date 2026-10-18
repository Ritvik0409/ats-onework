import 'package:flutter/material.dart';

/// Consistent snackbar feedback for the whole app.
///
/// Replaces the per-screen `_showSnack` copies that had drifted into
/// random colors (gold for errors, redAccent for successes). One place
/// owns the styling: success = green, failure = redAccent, neutral =
/// the app's champagne gold.
class AppSnack {
  AppSnack._();

  static void success(BuildContext context, String message) {
    _show(context, message, Colors.green.shade600, Colors.white);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, Colors.redAccent, Colors.white);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, const Color(0xFFD4AF37), Colors.black);
  }

  /// Escaped-hatch for pre-existing call sites that pass their own tint —
  /// uses black text like the legacy per-screen copies did.
  static void custom(BuildContext context, String message, Color background) {
    _show(context, message, background, Colors.black);
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
