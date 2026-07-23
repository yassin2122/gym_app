import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Centralized shadow definitions. Per the design system, hard drop
/// shadows are avoided — these are soft, wide, and low-opacity, used
/// sparingly (floating nav bar, sticky CTAs) rather than on every card.
abstract final class AppShadows {
  /// For elements that float above scrolling content — the bottom
  /// navigation bar, sticky action bars.
  static List<BoxShadow> floating = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.35),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// Subtle lift for cards that need to visually separate from a busy
  /// background (rare — most cards rely on surface-layer contrast alone,
  /// see DESIGN_SYSTEM.md's Elevation & shadow section).
  static List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.18),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}
