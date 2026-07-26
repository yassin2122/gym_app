-- CRITICAL: every view below is declared `security_invoker = true`.
-- Without this, a Postgres view runs with the view OWNER's privileges by
-- default, which would silently bypass every RLS policy on the
-- underlying tables — a serious security bug, not a style preference.
-- security_invoker makes the view enforce RLS as the querying user,
-- exactly like querying the base tables directly.

create view public.dashboard_view
  with (security_invoker = true) as
select
  p.id as user_id,
  p.display_name,
  coalesce(dc.current_streak_days, 0) as current_streak_days,
  coalesce(dc.longest_streak_days, 0) as longest_streak_days,
  coalesce(dc.workouts_this_week, 0) as workouts_this_week,
  dc.last_workout_at,
  ws.id as active_session_id,
  ws.name as active_session_name,
  ws.started_at as active_session_started_at
from public.profiles p
left join public.dashboard_cache dc on dc.user_id = p.id
left join lateral (
  select id, name, started_at
  from public.workout_sessions
  where user_id = p.id and status = 'in_progress'
  order by started_at desc
  limit 1
) ws on true;

create view public.history_view
  with (security_invoker = true) as
select
  s.id as session_id,
  s.user_id,
  s.name,
  s.status,
  s.started_at,
  s.completed_at,
  s.duration_seconds,
  s.total_volume_kg,
  t.name as template_name,
  count(distinct se.id) as exercise_count,
  count(st.id) as set_count
from public.workout_sessions s
left join public.workout_templates t on t.id = s.workout_template_id
left join public.workout_session_exercises se on se.workout_session_id = s.id and se.status <> 'removed'
left join public.workout_sets st on st.workout_session_exercise_id = se.id
group by s.id, t.name;

create view public.exercise_history_view
  with (security_invoker = true) as
select
  eh.user_id,
  eh.exercise_id,
  e.name as exercise_name,
  e.slug as exercise_slug,
  eh.times_performed,
  eh.last_performed_at,
  eh.best_weight_kg,
  eh.best_reps,
  eh.best_volume_kg
from public.exercise_history eh
join public.exercises e on e.id = eh.exercise_id;

create view public.personal_records_view
  with (security_invoker = true) as
select
  pr.id,
  pr.user_id,
  pr.exercise_id,
  e.name as exercise_name,
  e.slug as exercise_slug,
  pr.record_type,
  pr.value,
  pr.unit,
  pr.achieved_at,
  s.started_at as achieved_in_session_at
from public.personal_records pr
join public.exercises e on e.id = pr.exercise_id
left join public.workout_sets ws on ws.id = pr.workout_set_id
left join public.workout_session_exercises wse on wse.id = ws.workout_session_exercise_id
left join public.workout_sessions s on s.id = wse.workout_session_id;

create view public.statistics_view
  with (security_invoker = true) as
select
  user_id,
  period_type,
  period_start,
  total_workouts,
  total_volume_kg,
  total_sets,
  total_duration_seconds,
  muscle_group_distribution,
  computed_at
from public.statistics_cache;

create view public.favorite_exercises_view
  with (security_invoker = true) as
select
  f.user_id,
  f.created_at as favorited_at,
  e.id as exercise_id,
  e.name,
  e.slug,
  e.exercise_type,
  e.difficulty
from public.favorites f
join public.exercises e on e.id = f.exercise_id;
