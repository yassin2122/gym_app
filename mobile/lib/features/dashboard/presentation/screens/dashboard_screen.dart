import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/section_title.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      extendBodyBehindNav: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          SectionTitle(title: _greeting, subtitle: 'Ready to train today?')
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0, curve: Curves.easeOut),
          const SizedBox(height: AppSpacing.xl),
          _TodaysWorkoutCard().animate().fadeIn(delay: 80.ms, duration: 300.ms),
          const SizedBox(height: AppSpacing.md),
          const _QuickStartCard()
              .animate()
              .fadeIn(delay: 140.ms, duration: 300.ms),
          const SizedBox(height: AppSpacing.md),
          const _RecentActivityCard()
              .animate()
              .fadeIn(delay: 200.ms, duration: 300.ms),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _TodaysWorkoutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.calendar,
                  size: AppSizing.iconSm, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.xxs),
              Text('TODAY\'S WORKOUT', style: AppTypography.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('No workout scheduled', style: AppTypography.title),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Create a plan to see it here before your next session.',
            style: AppTypography.body,
          ),
        ],
      ),
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.surfaceElevated,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick Start', style: AppTypography.title),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Jump into an empty workout and log as you go.',
                  style: AppTypography.body,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 120,
            child: PrimaryButton(
              label: 'Start',
              // Placeholder-data screen — no business logic wired yet.
              onPressed: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.activity,
                  size: AppSizing.iconSm, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.xxs),
              Text('RECENT ACTIVITY', style: AppTypography.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('No workouts logged yet', style: AppTypography.title),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Your completed workouts will show up here.',
            style: AppTypography.body,
          ),
        ],
      ),
    );
  }
}
