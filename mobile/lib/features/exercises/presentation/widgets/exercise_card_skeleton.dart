import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Shimmer placeholder shaped like [ExerciseCard], shown while the first
/// page loads — telegraphs the real layout rather than a generic spinner,
/// per DESIGN_SYSTEM.md.
class ExerciseCardSkeleton extends StatelessWidget {
  const ExerciseCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const LoadingSkeleton(
            width: 64,
            height: 64,
            borderRadius: AppRadius.md,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                LoadingSkeleton(width: 160, height: 16),
                SizedBox(height: AppSpacing.xs),
                LoadingSkeleton(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
