import '../../../../core/error/failure.dart';
import '../../domain/entities/exercise_entity.dart';

/// Immutable state for the Exercise Library list. `items` accumulates
/// across pages (append-on-load-more); `isLoading` covers the initial/
/// search/filter-change fetch, `isLoadingMore` covers pagination only —
/// kept separate so the UI can show a skeleton for the former and a
/// small inline spinner for the latter, per DESIGN_SYSTEM.md.
final class ExerciseListState {
  const ExerciseListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextOffset = 0,
    this.error,
    this.searchQuery = '',
    this.selectedMuscle,
  });

  final List<ExerciseEntity> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int nextOffset;
  final Failure? error;
  final String searchQuery;
  final String? selectedMuscle;

  bool get isEmpty => !isLoading && error == null && items.isEmpty;

  ExerciseListState copyWith({
    List<ExerciseEntity>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? nextOffset,
    Failure? error,
    bool clearError = false,
    String? searchQuery,
    String? selectedMuscle,
    bool clearMuscle = false,
  }) {
    return ExerciseListState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextOffset: nextOffset ?? this.nextOffset,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedMuscle: clearMuscle ? null : (selectedMuscle ?? this.selectedMuscle),
    );
  }
}
