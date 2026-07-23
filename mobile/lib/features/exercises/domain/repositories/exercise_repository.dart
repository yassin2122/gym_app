import '../../../../core/error/result.dart';
import '../entities/exercise_entity.dart';

/// Contract for reading exercise library data. The domain and
/// presentation layers depend only on this interface — today it's
/// implemented against Supabase directly (see
/// [ExerciseRepositoryImpl]'s doc comment for why), but nothing above
/// this interface knows that.
abstract interface class ExerciseRepository {
  Future<Result<ExercisePage>> getExercises({
    String? search,
    List<String> primaryMuscles = const [],
    List<String> equipment = const [],
    String? exerciseType,
    int offset = 0,
    int limit = 30,
  });

  Future<Result<ExerciseFilterOptions>> getExerciseFilters();
}
