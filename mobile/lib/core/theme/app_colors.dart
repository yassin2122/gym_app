import 'package:flutter/material.dart';

/// Centralized color palette for the app.
///
/// This app is dark-mode only by design (see PRODUCT_VISION). Every screen
/// must reference these constants instead of hardcoding colors — this is
/// what lets us re-theme the whole app from one file later.
abstract final class AppColors {
  // Backgrounds — layered surface system (like Apple Fitness' depth cards)
  static const Color background = Color(0xFF0A0A0C);
  static const Color surface = Color(0xFF161618);
  static const Color surfaceElevated = Color(0xFF1F1F22);
  static const Color surfaceHighlight = Color(0xFF2A2A2E);

  // Brand / accent
  static const Color primary = Color(0xFF5E5CE6); // signature indigo accent
  static const Color primaryMuted = Color(0xFF3A3A8C);
  static const Color accentGreen = Color(0xFF32D74B); // streaks / success
  static const Color accentOrange = Color(0xFFFF9F0A); // RPE / intensity
  static const Color accentRed = Color(0xFFFF453A); // errors / destructive

  // Text
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA1A1A6);
  static const Color textTertiary = Color(0xFF6E6E73);
  static const Color textDisabled = Color(0xFF48484A);

  // Borders / dividers
  static const Color border = Color(0xFF2C2C2E);
  static const Color divider = Color(0xFF1F1F21);

  // Semantic
  static const Color success = accentGreen;
  static const Color warning = accentOrange;
  static const Color error = accentRed;

  // Overlays
  static const Color overlayScrim = Color(0xB3000000); // 70% black
  static const Color shimmerBase = Color(0xFF1A1A1C);
  static const Color shimmerHighlight = Color(0xFF262628);

  // Navigation
  static const Color navBarBackground = Color(0xF01C1C1F); // ~94% opaque surfaceElevated
  static const Color navBarSelected = primary;
  static const Color navBarUnselected = textTertiary;

  // Shadow
  static const Color shadow = Color(0xFF000000);
}
