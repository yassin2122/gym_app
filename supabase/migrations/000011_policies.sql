-- ============================================================
-- Profiles & personal data — owner-only, full CRUD on own rows.
-- Every UPDATE policy has WITH CHECK, not just USING: USING alone
-- only gates which existing rows can be targeted, not what the row
-- is allowed to become — without WITH CHECK a user could rewrite
-- their own row's id/user_id to point at someone else. See the
-- original Sprint 1 security hardening notes for the full incident
-- this pattern was learned from.
-- ============================================================

alter table public.profiles enable row level security;
create policy "profiles_select_own" on public.profiles for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid() = id);

alter table public.user_preferences enable row level security;
create policy "user_preferences_select_own" on public.user_preferences for select using (auth.uid() = user_id);
create policy "user_preferences_update_own" on public.user_preferences for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_preferences_insert_own" on public.user_preferences for insert with check (auth.uid() = user_id);

alter table public.body_measurements enable row level security;
create policy "body_measurements_select_own" on public.body_measurements for select using (auth.uid() = user_id);
create policy "body_measurements_insert_own" on public.body_measurements for insert with check (auth.uid() = user_id);
create policy "body_measurements_update_own" on public.body_measurements for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "body_measurements_delete_own" on public.body_measurements for delete using (auth.uid() = user_id);

alter table public.weight_history enable row level security;
create policy "weight_history_select_own" on public.weight_history for select using (auth.uid() = user_id);
create policy "weight_history_insert_own" on public.weight_history for insert with check (auth.uid() = user_id);
create policy "weight_history_update_own" on public.weight_history for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "weight_history_delete_own" on public.weight_history for delete using (auth.uid() = user_id);

-- ============================================================
-- Reference/taxonomy tables — shared read-only data. Any
-- authenticated user (including guests — Supabase anonymous
-- sessions carry the `authenticated` Postgres role) can read;
-- only service_role can write, matching the exercise library's
-- own write policy below.
-- ============================================================

alter table public.muscle_groups enable row level security;
create policy "muscle_groups_select_all" on public.muscle_groups for select using (auth.role() = 'authenticated');
create policy "muscle_groups_service_write" on public.muscle_groups for insert with check (auth.role() = 'service_role');

alter table public.equipment enable row level security;
create policy "equipment_select_all" on public.equipment for select using (auth.role() = 'authenticated');
create policy "equipment_service_write" on public.equipment for insert with check (auth.role() = 'service_role');

alter table public.exercise_categories enable row level security;
create policy "exercise_categories_select_all" on public.exercise_categories for select using (auth.role() = 'authenticated');
create policy "exercise_categories_service_write" on public.exercise_categories for insert with check (auth.role() = 'service_role');

alter table public.exercise_tags enable row level security;
create policy "exercise_tags_select_all" on public.exercise_tags for select using (auth.role() = 'authenticated');
create policy "exercise_tags_service_write" on public.exercise_tags for insert with check (auth.role() = 'service_role');

-- ============================================================
-- Exercise library — shared read-only reference data. Same
-- pattern as the original MVP exercises table: readable by any
-- authenticated user, writable only by service_role (no
-- user-created exercises yet — is_custom/created_by are schema-
-- ready for when that feature is built, at which point these
-- policies need a second INSERT/UPDATE branch for
-- `created_by = auth.uid()`, not a redesign).
-- ============================================================

alter table public.exercises enable row level security;
create policy "exercises_select_all" on public.exercises for select using (auth.role() = 'authenticated');
create policy "exercises_service_write" on public.exercises for insert with check (auth.role() = 'service_role');
create policy "exercises_service_update" on public.exercises for update using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

alter table public.exercise_aliases enable row level security;
create policy "exercise_aliases_select_all" on public.exercise_aliases for select using (auth.role() = 'authenticated');
create policy "exercise_aliases_service_write" on public.exercise_aliases for insert with check (auth.role() = 'service_role');

alter table public.exercise_images enable row level security;
create policy "exercise_images_select_all" on public.exercise_images for select using (auth.role() = 'authenticated');
create policy "exercise_images_service_write" on public.exercise_images for insert with check (auth.role() = 'service_role');

alter table public.exercise_videos enable row level security;
create policy "exercise_videos_select_all" on public.exercise_videos for select using (auth.role() = 'authenticated');
create policy "exercise_videos_service_write" on public.exercise_videos for insert with check (auth.role() = 'service_role');

alter table public.exercise_muscles enable row level security;
create policy "exercise_muscles_select_all" on public.exercise_muscles for select using (auth.role() = 'authenticated');
create policy "exercise_muscles_service_write" on public.exercise_muscles for insert with check (auth.role() = 'service_role');

alter table public.exercise_equipment enable row level security;
create policy "exercise_equipment_select_all" on public.exercise_equipment for select using (auth.role() = 'authenticated');
create policy "exercise_equipment_service_write" on public.exercise_equipment for insert with check (auth.role() = 'service_role');

alter table public.exercise_tag_map enable row level security;
create policy "exercise_tag_map_select_all" on public.exercise_tag_map for select using (auth.role() = 'authenticated');
create policy "exercise_tag_map_service_write" on public.exercise_tag_map for insert with check (auth.role() = 'service_role');

alter table public.exercise_progressions enable row level security;
create policy "exercise_progressions_select_all" on public.exercise_progressions for select using (auth.role() = 'authenticated');
create policy "exercise_progressions_service_write" on public.exercise_progressions for insert with check (auth.role() = 'service_role');

alter table public.exercise_regressions enable row level security;
create policy "exercise_regressions_select_all" on public.exercise_regressions for select using (auth.role() = 'authenticated');
create policy "exercise_regressions_service_write" on public.exercise_regressions for insert with check (auth.role() = 'service_role');

alter table public.exercise_alternatives enable row level security;
create policy "exercise_alternatives_select_all" on public.exercise_alternatives for select using (auth.role() = 'authenticated');
create policy "exercise_alternatives_service_write" on public.exercise_alternatives for insert with check (auth.role() = 'service_role');

-- ============================================================
-- Workout tracking — strictly owner-only.
-- ============================================================

alter table public.workout_sessions enable row level security;
create policy "workout_sessions_select_own" on public.workout_sessions for select using (auth.uid() = user_id);
create policy "workout_sessions_insert_own" on public.workout_sessions for insert with check (auth.uid() = user_id);
create policy "workout_sessions_update_own" on public.workout_sessions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "workout_sessions_delete_own" on public.workout_sessions for delete using (auth.uid() = user_id);

alter table public.workout_session_exercises enable row level security;
create policy "session_exercises_select_own" on public.workout_session_exercises for select
  using (exists (select 1 from public.workout_sessions s where s.id = workout_session_id and s.user_id = auth.uid()));
create policy "session_exercises_all_own" on public.workout_session_exercises for all
  using (exists (select 1 from public.workout_sessions s where s.id = workout_session_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.workout_sessions s where s.id = workout_session_id and s.user_id = auth.uid()));

alter table public.workout_sets enable row level security;
create policy "workout_sets_select_own" on public.workout_sets for select
  using (exists (
    select 1 from public.workout_session_exercises se
    join public.workout_sessions s on s.id = se.workout_session_id
    where se.id = workout_session_exercise_id and s.user_id = auth.uid()
  ));
create policy "workout_sets_all_own" on public.workout_sets for all
  using (exists (
    select 1 from public.workout_session_exercises se
    join public.workout_sessions s on s.id = se.workout_session_id
    where se.id = workout_session_exercise_id and s.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.workout_session_exercises se
    join public.workout_sessions s on s.id = se.workout_session_id
    where se.id = workout_session_exercise_id and s.user_id = auth.uid()
  ));

-- ============================================================
-- Templates — system templates (user_id null) visible to all;
-- user-owned templates visible/editable by their owner only.
-- ============================================================

alter table public.workout_templates enable row level security;
create policy "workout_templates_select" on public.workout_templates for select
  using (user_id is null or user_id = auth.uid() or is_public = true);
create policy "workout_templates_insert_own" on public.workout_templates for insert with check (auth.uid() = user_id);
create policy "workout_templates_update_own" on public.workout_templates for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "workout_templates_delete_own" on public.workout_templates for delete using (auth.uid() = user_id);

alter table public.template_exercises enable row level security;
create policy "template_exercises_select" on public.template_exercises for select
  using (exists (
    select 1 from public.workout_templates t
    where t.id = workout_template_id and (t.user_id is null or t.user_id = auth.uid() or t.is_public = true)
  ));
create policy "template_exercises_all_own" on public.template_exercises for all
  using (exists (select 1 from public.workout_templates t where t.id = workout_template_id and t.user_id = auth.uid()))
  with check (exists (select 1 from public.workout_templates t where t.id = workout_template_id and t.user_id = auth.uid()));

-- ============================================================
-- Favorites — strictly owner-only.
-- ============================================================

alter table public.favorites enable row level security;
create policy "favorites_select_own" on public.favorites for select using (auth.uid() = user_id);
create policy "favorites_insert_own" on public.favorites for insert with check (auth.uid() = user_id);
create policy "favorites_delete_own" on public.favorites for delete using (auth.uid() = user_id);

-- ============================================================
-- Cache tables — read-only to users. All writes happen through
-- SECURITY DEFINER functions (update_personal_record,
-- update_exercise_history, update_statistics, dashboard_summary)
-- called by triggers, never by direct user INSERT/UPDATE. This is
-- the enforcement mechanism for "these are caches, not
-- user-editable data" — there is deliberately no INSERT/UPDATE
-- policy for the authenticated role on any of these four tables.
-- ============================================================

alter table public.personal_records enable row level security;
create policy "personal_records_select_own" on public.personal_records for select using (auth.uid() = user_id);

alter table public.exercise_history enable row level security;
create policy "exercise_history_select_own" on public.exercise_history for select using (auth.uid() = user_id);

alter table public.statistics_cache enable row level security;
create policy "statistics_cache_select_own" on public.statistics_cache for select using (auth.uid() = user_id);

alter table public.dashboard_cache enable row level security;
create policy "dashboard_cache_select_own" on public.dashboard_cache for select using (auth.uid() = user_id);
