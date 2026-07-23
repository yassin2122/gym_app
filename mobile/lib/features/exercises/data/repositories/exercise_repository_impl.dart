import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/exercise_entity.dart';
import '../../domain/repositories/exercise_repository.dart';
import '../datasources/exercise_remote_datasource.dart';
import '../models/exercise_model.dart';

/// Concrete [ExerciseRepository]. See [ExerciseRemoteDataSource]'s doc
/// comment for the Supabase-direct implementation decision — this class
/// is the boundary that would need to change (not the interface) if the
/// FastAPI backend is finished later.
class ExerciseRepositoryImpl implements ExerciseRepository {
  const ExerciseRepositoryImpl(this._remoteDataSource);

  final ExerciseRemoteDataSource _remoteDataSource;

  @override
  Future<Result<ExercisePage>> getExercises({
    String? search,
    List<String> primaryMuscles = const [],
    List<String> equipment = const [],
    String? exerciseType,
    int offset = 0,
    int limit = 30,
  }) async {
    try {
      // Fetch one extra row to determine hasMore without a separate count
      // query — the same technique used by the FastAPI cursor design in
      // API_CONTRACT.md, adapted to offset pagination.
      final rows = await _remoteDataSource.fetchExercises(
        search: search,
        primaryMuscles: primaryMuscles,
        equipment: equipment,
        exerciseType: exerciseType,
        offset: offset,
        limit: limit + 1,
      );

      final hasMore = rows.length > limit;
      final pageRows = hasMore ? rows.sublist(0, limit) : rows;
      final items = pageRows.map(ExerciseModel.fromRow).toList();

      return Result.success(ExercisePage(
        items: items,
        hasMore: hasMore,
        nextOffset: offset + items.length,
      ));
    } on NetworkException {
      return const Result.failure(NetworkFailure());
    } on ServerException catch (e) {
      return Result.failure(ServerFailure(e.message));
    } catch (_) {
      return const Result.failure(UnknownFailure());
    }
  }

  @override
  Future<Result<ExerciseFilterOptions>> getExerciseFilters() async {
    try {
      final rows = await _remoteDataSource.fetchFacetColumns();

      final muscles = <String>{};
      final equipment = <String>{};
      final types = <String>{};
      for (final row in rows) {
        muscles.add(row['primary_muscle'] as String);
        equipment.add(row['equipment'] as String);
        types.add(row['exercise_type'] as String);
      }

      return Result.success(ExerciseFilterOptions(
        primaryMuscles: muscles.toList()..sort(),
        equipment: equipment.toList()..sort(),
        exerciseTypes: types.toList()..sort(),
      ));
    } on NetworkException {
      return const Result.failure(NetworkFailure());
    } on ServerException catch (e) {
      return Result.failure(ServerFailure(e.message));
    } catch (_) {
      return const Result.failure(UnknownFailure());
    }
  }
}
