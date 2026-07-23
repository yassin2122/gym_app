import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../../../../core/error/exceptions.dart';

/// Wraps raw Supabase/PostgREST calls against `public.exercises`. This is
/// the ONLY place in the exercises feature that talks to Supabase
/// directly — everything above it (repository, use cases, presentation)
/// only knows [ExerciseRepository]'s interface.
///
/// Implementation note: this queries Supabase directly rather than the
/// FastAPI backend described in API_CONTRACT.md, because the backend
/// was left unfinished. RLS (verified in Phase 1) governs access exactly
/// as it would through FastAPI's RLS-aware connection — a guest or
/// signed-in user can read, nothing can write except service_role. If/
/// when FastAPI is finished, only this file changes.
class ExerciseRemoteDataSource {
  const ExerciseRemoteDataSource(this._client);

  final supabase.SupabaseClient _client;

  static const _summaryColumns =
      'id, name, primary_muscle, secondary_muscles, equipment, exercise_type, gif_url';

  Future<List<Map<String, dynamic>>> fetchExercises({
    String? search,
    List<String> primaryMuscles = const [],
    List<String> equipment = const [],
    String? exerciseType,
    required int offset,
    required int limit,
  }) async {
    try {
      var query = _client.from('exercises').select(_summaryColumns);

      if (search != null && search.trim().isNotEmpty) {
        query = query.ilike('name', '%${search.trim()}%');
      }
      if (primaryMuscles.isNotEmpty) {
        query = query.in_('primary_muscle', primaryMuscles);
      }
      if (equipment.isNotEmpty) {
        query = query.in_('equipment', equipment);
      }
      if (exerciseType != null) {
        query = query.eq('exercise_type', exerciseType);
      }

      final rows = await query
          .order('name', ascending: true)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(rows as List);
    } on supabase.PostgrestException catch (e) {
      throw ServerException(e.message);
    } catch (_) {
      throw const NetworkException();
    }
  }

  /// Computes distinct facet values client-side from a slim query — see
  /// the repository's doc comment for why (PostgREST's query builder
  /// doesn't expose a `DISTINCT` modifier). ~150 rows makes this cheap.
  Future<List<Map<String, dynamic>>> fetchFacetColumns() async {
    try {
      final rows = await _client
          .from('exercises')
          .select('primary_muscle, equipment, exercise_type');
      return List<Map<String, dynamic>>.from(rows as List);
    } on supabase.PostgrestException catch (e) {
      throw ServerException(e.message);
    } catch (_) {
      throw const NetworkException();
    }
  }
}
