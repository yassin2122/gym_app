-- ============================================================
-- calculate_workout_volume — total kg lifted in a session,
-- excluding warmup sets. Pure read, no side effects.
-- ============================================================
create or replace function public.calculate_workout_volume(p_session_id uuid)
returns numeric
language sql
stable
as $$
  select coalesce(sum(ws.weight_kg * ws.reps), 0)
  from public.workout_sets ws
  join public.workout_session_exercises wse on wse.id = ws.workout_session_exercise_id
  where wse.workout_session_id = p_session_id
    and ws.is_warmup = false
    and ws.weight_kg is not null;
$$;

-- ============================================================
-- update_personal_record — checks one newly-logged set against
-- the user's current records for that exercise and upserts
-- personal_records if beaten. SECURITY DEFINER: personal_records
-- is read-only to users via RLS (see 000011_policies.sql) —
-- writes only happen here, called by the trigger in
-- 000010_triggers.sql after every set insert.
-- ============================================================
create or replace function public.update_personal_record(p_set_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid;
  v_exercise_id uuid;
  v_weight numeric;
  v_reps integer;
  v_volume numeric;
  v_estimated_1rm numeric;
begin
  select s.user_id, wse.exercise_id, ws.weight_kg, ws.reps,
         coalesce(ws.weight_kg, 0) * ws.reps
  into v_user_id, v_exercise_id, v_weight, v_reps, v_volume
  from public.workout_sets ws
  join public.workout_session_exercises wse on wse.id = ws.workout_session_exercise_id
  join public.workout_sessions s on s.id = wse.workout_session_id
  where ws.id = p_set_id and ws.is_warmup = false;

  if v_user_id is null then
    return; -- warmup set or not found — no PR consideration
  end if;

  -- max_weight
  if v_weight is not null then
    insert into public.personal_records (user_id, exercise_id, record_type, value, unit, workout_set_id, achieved_at)
    values (v_user_id, v_exercise_id, 'max_weight', v_weight, 'kg', p_set_id, now())
    on conflict (user_id, exercise_id, record_type)
    do update set value = excluded.value, workout_set_id = excluded.workout_set_id, achieved_at = excluded.achieved_at
    where excluded.value > public.personal_records.value;
  end if;

  -- max_reps
  insert into public.personal_records (user_id, exercise_id, record_type, value, unit, workout_set_id, achieved_at)
  values (v_user_id, v_exercise_id, 'max_reps', v_reps, 'reps', p_set_id, now())
  on conflict (user_id, exercise_id, record_type)
  do update set value = excluded.value, workout_set_id = excluded.workout_set_id, achieved_at = excluded.achieved_at
  where excluded.value > public.personal_records.value;

  -- max_volume (single-set volume: weight * reps)
  if v_weight is not null then
    insert into public.personal_records (user_id, exercise_id, record_type, value, unit, workout_set_id, achieved_at)
    values (v_user_id, v_exercise_id, 'max_volume', v_volume, 'kg', p_set_id, now())
    on conflict (user_id, exercise_id, record_type)
    do update set value = excluded.value, workout_set_id = excluded.workout_set_id, achieved_at = excluded.achieved_at
    where excluded.value > public.personal_records.value;
  end if;

  -- estimated_1rm via the Epley formula: weight * (1 + reps/30).
  -- A standard, well-documented estimation formula — not a fabricated
  -- number — but still an estimate, surfaced to the user as such.
  if v_weight is not null and v_reps > 0 then
    v_estimated_1rm := v_weight * (1 + v_reps::numeric / 30);
    insert into public.personal_records (user_id, exercise_id, record_type, value, unit, workout_set_id, achieved_at)
    values (v_user_id, v_exercise_id, 'estimated_1rm', v_estimated_1rm, 'kg', p_set_id, now())
    on conflict (user_id, exercise_id, record_type)
    do update set value = excluded.value, workout_set_id = excluded.workout_set_id, achieved_at = excluded.achieved_at
    where excluded.value > public.personal_records.value;
  end if;
end;
$$;

-- ============================================================
-- update_exercise_history — rolls up a user's cumulative stats
-- for one exercise after a set is logged. SECURITY DEFINER for
-- the same reason as update_personal_record.
-- ============================================================
create or replace function public.update_exercise_history(p_set_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid;
  v_exercise_id uuid;
begin
  select s.user_id, wse.exercise_id
  into v_user_id, v_exercise_id
  from public.workout_sets ws
  join public.workout_session_exercises wse on wse.id = ws.workout_session_exercise_id
  join public.workout_sessions s on s.id = wse.workout_session_id
  where ws.id = p_set_id;

  if v_user_id is null then
    return;
  end if;

  insert into public.exercise_history (user_id, exercise_id, times_performed, last_performed_at, best_weight_kg, best_reps, best_volume_kg, updated_at)
  select
    v_user_id,
    v_exercise_id,
    count(distinct wse.workout_session_id),
    max(ws.completed_at),
    max(ws.weight_kg),
    max(ws.reps),
    max(coalesce(ws.weight_kg, 0) * ws.reps),
    now()
  from public.workout_sets ws
  join public.workout_session_exercises wse on wse.id = ws.workout_session_exercise_id
  where wse.exercise_id = v_exercise_id
    and wse.workout_session_id in (select id from public.workout_sessions where user_id = v_user_id)
    and ws.is_warmup = false
  on conflict (user_id, exercise_id)
  do update set
    times_performed = excluded.times_performed,
    last_performed_at = excluded.last_performed_at,
    best_weight_kg = excluded.best_weight_kg,
    best_reps = excluded.best_reps,
    best_volume_kg = excluded.best_volume_kg,
    updated_at = now();
end;
$$;

-- ============================================================
-- update_statistics — recomputes week/month/all_time aggregates
-- for a user. SECURITY DEFINER: statistics_cache is read-only to
-- users via RLS.
-- ============================================================
create or replace function public.update_statistics(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_period record;
begin
  for v_period in
    select * from (values
      ('week', date_trunc('week', now())::date),
      ('month', date_trunc('month', now())::date),
      ('all_time', date '1970-01-01')
    ) as t(period_type, period_start)
  loop
    insert into public.statistics_cache (
      user_id, period_type, period_start, total_workouts, total_volume_kg,
      total_sets, total_duration_seconds, muscle_group_distribution, computed_at
    )
    with period_sessions as (
      select id, total_volume_kg, duration_seconds
      from public.workout_sessions
      where user_id = p_user_id
        and status = 'completed'
        and (v_period.period_type = 'all_time' or started_at >= v_period.period_start)
    ),
    set_totals as (
      select count(ws.id) as total_sets
      from period_sessions ps
      join public.workout_session_exercises wse on wse.workout_session_id = ps.id
      join public.workout_sets ws on ws.workout_session_exercise_id = wse.id
    ),
    muscle_dist as (
      select mg.name, count(*) as cnt
      from period_sessions ps
      join public.workout_session_exercises wse on wse.workout_session_id = ps.id
      join public.exercise_muscles em on em.exercise_id = wse.exercise_id and em.role = 'primary'
      join public.muscle_groups mg on mg.id = em.muscle_group_id
      group by mg.name
    )
    select
      p_user_id,
      v_period.period_type,
      v_period.period_start,
      (select count(*) from period_sessions),
      (select coalesce(sum(total_volume_kg), 0) from period_sessions),
      (select coalesce(total_sets, 0) from set_totals),
      (select coalesce(sum(duration_seconds), 0) from period_sessions),
      (select coalesce(jsonb_object_agg(name, cnt), '{}'::jsonb) from muscle_dist),
      now()
    on conflict (user_id, period_type, period_start)
    do update set
      total_workouts = excluded.total_workouts,
      total_volume_kg = excluded.total_volume_kg,
      total_sets = excluded.total_sets,
      total_duration_seconds = excluded.total_duration_seconds,
      muscle_group_distribution = excluded.muscle_group_distribution,
      computed_at = now();
  end loop;
end;
$$;

-- ============================================================
-- dashboard_summary — recomputes streaks and this-week count.
-- SECURITY DEFINER: dashboard_cache is read-only to users.
-- ============================================================
create or replace function public.dashboard_summary(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_workout_dates date[];
  v_current_streak integer := 0;
  v_longest_streak integer := 0;
  v_running integer := 0;
  v_prev date;
  v_d date;
  v_this_week integer;
  v_last_workout timestamptz;
begin
  select array_agg(distinct started_at::date order by started_at::date desc)
  into v_workout_dates
  from public.workout_sessions
  where user_id = p_user_id and status = 'completed';

  if v_workout_dates is not null then
    v_prev := null;
    foreach v_d in array v_workout_dates loop
      if v_prev is null or v_prev - v_d = 1 then
        v_running := v_running + 1;
      else
        v_running := 1;
      end if;
      v_longest_streak := greatest(v_longest_streak, v_running);
      v_prev := v_d;
    end loop;

    -- Current streak only counts if it includes today or yesterday —
    -- otherwise the streak has already been broken.
    if v_workout_dates[1] >= current_date - 1 then
      v_current_streak := 1;
      for i in 2..array_length(v_workout_dates, 1) loop
        if v_workout_dates[i-1] - v_workout_dates[i] = 1 then
          v_current_streak := v_current_streak + 1;
        else
          exit;
        end if;
      end loop;
    end if;
  end if;

  select count(*), max(started_at)
  into v_this_week, v_last_workout
  from public.workout_sessions
  where user_id = p_user_id
    and status = 'completed'
    and started_at >= date_trunc('week', now());

  insert into public.dashboard_cache (user_id, current_streak_days, longest_streak_days, workouts_this_week, last_workout_at, computed_at)
  values (p_user_id, v_current_streak, v_longest_streak, coalesce(v_this_week, 0), v_last_workout, now())
  on conflict (user_id)
  do update set
    current_streak_days = excluded.current_streak_days,
    longest_streak_days = greatest(public.dashboard_cache.longest_streak_days, excluded.longest_streak_days),
    workouts_this_week = excluded.workouts_this_week,
    last_workout_at = excluded.last_workout_at,
    computed_at = now();
end;
$$;

-- ============================================================
-- exercise_search — full text + trigram ranked search. SECURITY
-- INVOKER (default) — respects the caller's own RLS, same as
-- querying public.exercises directly.
-- ============================================================
create or replace function public.exercise_search(p_query text, p_limit integer default 30, p_offset integer default 0)
returns setof public.exercises
language sql
stable
as $$
  select e.*
  from public.exercises e
  where p_query is null or p_query = ''
     or e.search_vector @@ plainto_tsquery('english', unaccent(p_query))
     or e.name % unaccent(p_query)
  order by
    case when p_query is null or p_query = '' then 0
    else ts_rank(e.search_vector, plainto_tsquery('english', unaccent(p_query))) end desc,
    similarity(e.name, coalesce(p_query, '')) desc,
    e.popularity desc,
    e.name asc
  limit p_limit offset p_offset;
$$;

-- ============================================================
-- recent_workouts — SECURITY INVOKER, thin RPC convenience
-- wrapper over history_view for the Dashboard's recent list.
-- ============================================================
create or replace function public.recent_workouts(p_user_id uuid, p_limit integer default 10)
returns setof public.history_view
language sql
stable
as $$
  select * from public.history_view
  where user_id = p_user_id
  order by started_at desc
  limit p_limit;
$$;

-- ============================================================
-- favorite_toggle — SECURITY INVOKER; the underlying insert/
-- delete is governed by the normal favorites RLS policies, so
-- this cannot be used to favorite on another user's behalf.
-- Returns true if now favorited, false if removed.
-- ============================================================
create or replace function public.favorite_toggle(p_user_id uuid, p_exercise_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_existing uuid;
begin
  select id into v_existing
  from public.favorites
  where user_id = p_user_id and exercise_id = p_exercise_id;

  if v_existing is not null then
    delete from public.favorites where id = v_existing;
    return false;
  else
    insert into public.favorites (user_id, exercise_id) values (p_user_id, p_exercise_id);
    return true;
  end if;
end;
$$;

-- ============================================================
-- session_summary — single-row RPC convenience wrapper over
-- history_view, for a "workout finished" summary screen.
-- ============================================================
create or replace function public.session_summary(p_session_id uuid)
returns public.history_view
language sql
stable
as $$
  select * from public.history_view where session_id = p_session_id;
$$;

-- ============================================================
-- history_summary — paginated wrapper over history_view.
-- ============================================================
create or replace function public.history_summary(p_user_id uuid, p_limit integer default 20, p_offset integer default 0)
returns setof public.history_view
language sql
stable
as $$
  select * from public.history_view
  where user_id = p_user_id
  order by started_at desc
  limit p_limit offset p_offset;
$$;
