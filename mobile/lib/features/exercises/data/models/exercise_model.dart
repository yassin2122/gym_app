import '../../domain/entities/exercise_entity.dart';

/// Maps a raw row (as returned by supabase_flutter's PostgREST client —
/// a `Map<String, dynamic>` with snake_case keys matching the Postgres
/// columns directly) to the domain entity. This is the translation
/// boundary — nothing outside the data layer should parse raw rows.
final class ExerciseModel {
  const ExerciseModel._();

  static ExerciseEntity fromRow(Map<String, dynamic> row) {
    return ExerciseEntity(
      id: row['id'] as String,
      name: row['name'] as String,
      primaryMuscle: row['primary_muscle'] as String,
      secondaryMuscles: List<String>.from(
        row['secondary_muscles'] as List? ?? const [],
      ),
      equipment: row['equipment'] as String,
      exerciseType: row['exercise_type'] as String,
      gifUrl: row['gif_url'] as String?,
      instructions: row['instructions'] as String?,
      isCustom: row['is_custom'] as bool? ?? false,
    );
  }
}
