import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Shared title + subtitle header for Login/Register/Forgot Password
/// screens, kept in one widget so the entry animation and spacing stay
/// identical across all three.
class AuthHeader extends StatelessWidget {
  const AuthHeader({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.displayMedium)
            .animate()
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: AppTypography.body)
            .animate()
            .fadeIn(delay: 100.ms, duration: 300.ms),
      ],
    );
  }
}
