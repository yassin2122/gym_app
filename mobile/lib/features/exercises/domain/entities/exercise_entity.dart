/// Domain-level representation of an exercise. Used for both list
/// (summary) and detail contexts — `instructions` is simply absent
/// (null) when fetched as part of a list, since the list query never
/// requests that column.
final class ExerciseEntity {
  const ExerciseEntity({
    required this.id,
    required this.name,
    required this.primaryMuscle,
    required this.secondaryMuscles,
    required this.equipment,
    required this.exerciseType,
    this.gifUrl,
    this.instructions,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String primaryMuscle;
  final List<String> secondaryMuscles;
  final String equipment;
  final String exerciseType;
  final String? gifUrl;
  final String? instructions;
  final bool isCustom;
}

/// One page of exercise results plus enough state to fetch the next page.
final class ExercisePage {
  const ExercisePage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });

  final List<ExerciseEntity> items;
  final bool hasMore;

  /// Offset to request for the next page. See the repository doc comment
  /// for why this is offset-based rather than the cursor design in
  /// API_CONTRACT.md — a deliberate adaptation for the direct-Supabase
  /// implementation used this sprint.
  final int nextOffset;
}

/// Distinct facet values actually present in the library — powers the
/// filter UI without hardcoding a taxonomy, per API_CONTRACT.md.
final class ExerciseFilterOptions {
  const ExerciseFilterOptions({
    required this.primaryMuscles,
    required this.equipment,
    required this.exerciseTypes,
  });

  final List<String> primaryMuscles;
  final List<String> equipment;
  final List<String> exerciseTypes;

  static const empty = ExerciseFilterOptions(
    primaryMuscles: [],
    equipment: [],
    exerciseTypes: [],
  );
}
