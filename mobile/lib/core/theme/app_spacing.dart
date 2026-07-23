/// Spacing scale used across the app. Always reference these instead of
/// raw numbers so spacing stays consistent as the app grows (8pt grid).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Standard horizontal screen padding.
  static const double screenPadding = md;
}

/// Corner radius scale. Large rounded cards are a core design principle.
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// Standard touch target sizing — must stay large per the design system.
abstract final class AppSizing {
  static const double minTouchTarget = 48;
  static const double buttonHeight = 56;
  static const double inputHeight = 56;
  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;
}
