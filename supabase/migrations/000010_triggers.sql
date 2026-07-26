-- ============================================================
-- Generic updated_at maintenance
-- ============================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger set_user_preferences_updated_at before update on public.user_preferences
  for each row execute function public.set_updated_at();
create trigger set_exercises_updated_at before update on public.exercises
  for each row execute function public.set_updated_at();
create trigger set_workout_templates_updated_at before update on public.workout_templates
  for each row execute function public.set_updated_at();

-- ============================================================
-- Exercise search_vector maintenance (base fields)
-- ============================================================
create or replace function public.handle_exercise_search_base()
returns trigger
language plpgsql
as $$
begin
  new.search_vector := to_tsvector('english',
    unaccent(coalesce(new.name, '')) || ' ' ||
    unaccent(coalesce(new.description, '')) || ' ' ||
    unaccent(array_to_string(coalesce(new.instructions, '{}'), ' '))
  );
  return new;
end;
$$;

create trigger exercise_search_base_trigger
  before insert or update of name, description, instructions on public.exercises
  for each row execute function public.handle_exercise_search_base();

-- Incrementally folds a muscle/equipment name into an exercise's
-- existing search_vector rather than recomputing from scratch — cheap,
-- and correct because tsvector concatenation (||) is idempotent-safe
-- for our purposes (duplicate lexemes just don't add new matches).
create or replace function public.handle_exercise_search_append()
returns trigger
language plpgsql
as $$
declare
  v_exercise_id uuid;
  v_term text;
begin
  v_exercise_id := coalesce(new.exercise_id, old.exercise_id);

  if TG_TABLE_NAME = 'exercise_muscles' then
    select name into v_term from public.muscle_groups where id = coalesce(new.muscle_group_id, old.muscle_group_id);
  else
    select name into v_term from public.equipment where id = coalesce(new.equipment_id, old.equipment_id);
  end if;

  update public.exercises
  set search_vector = search_vector || to_tsvector('english', unaccent(coalesce(v_term, '')))
  where id = v_exercise_id;

  return coalesce(new, old);
end;
$$;

create trigger exercise_muscles_search_trigger
  after insert on public.exercise_muscles
  for each row execute function public.handle_exercise_search_append();

create trigger exercise_equipment_search_trigger
  after insert on public.exercise_equipment
  for each row execute function public.handle_exercise_search_append();

-- ============================================================
-- body_region denormalization: kept in sync with the exercise's
-- primary muscle. See 000004_exercises.sql's comment on why this
-- is denormalized at all.
-- ============================================================
create or replace function public.sync_exercise_body_region()
returns trigger
language plpgsql
as $$
begin
  if new.role = 'primary' then
    update public.exercises
    set body_region = (select body_region from public.muscle_groups where id = new.muscle_group_id)
    where id = new.exercise_id;
  end if;
  return new;
end;
$$;

create trigger sync_exercise_body_region_trigger
  after insert on public.exercise_muscles
  for each row execute function public.sync_exercise_body_region();

-- exercise_type denormalization: kept in sync if category_id changes
-- after initial insert (the importer sets exercise_type directly at
-- insert time — this trigger only handles the edit-after-the-fact case).
create or replace function public.sync_exercise_type_from_category()
returns trigger
language plpgsql
as $$
declare
  v_category_name text;
begin
  if new.category_id is distinct from old.category_id then
    select name into v_category_name from public.exercise_categories where id = new.category_id;
    new.exercise_type := case
      when v_category_name in ('strength', 'powerlifting', 'olympic_weightlifting', 'strongman', 'plyometrics') then 'strength'
      when v_category_name = 'cardio' then 'cardio'
      when v_category_name = 'stretching' then 'mobility'
      else new.exercise_type
    end;
  end if;
  return new;
end;
$$;

create trigger sync_exercise_type_trigger
  before update of category_id on public.exercises
  for each row execute function public.sync_exercise_type_from_category();

-- ============================================================
-- workout_sessions: auto-complete duration, touch last_activity_at
-- ============================================================
create or replace function public.handle_workout_session_completion()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'completed' and old.status <> 'completed' then
    if new.completed_at is null then
      new.completed_at := now();
    end if;
    new.duration_seconds := extract(epoch from (new.completed_at - new.started_at))::integer;
  end if;
  new.last_activity_at := now();
  return new;
end;
$$;

create trigger workout_session_completion_trigger
  before update on public.workout_sessions
  for each row execute function public.handle_workout_session_completion();

-- After a session completes, refresh the cache tables that summarize
-- completed workouts. Runs AFTER so it sees the committed row.
create or replace function public.handle_workout_session_completed_after()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'completed' and old.status <> 'completed' then
    perform public.update_statistics(new.user_id);
    perform public.dashboard_summary(new.user_id);
  end if;
  return new;
end;
$$;

create trigger workout_session_completed_after_trigger
  after update on public.workout_sessions
  for each row execute function public.handle_workout_session_completed_after();

-- ============================================================
-- workout_session_exercises: touch the parent session's
-- last_activity_at whenever exercises are added/removed/skipped
-- mid-workout.
-- ============================================================
create or replace function public.touch_session_activity()
returns trigger
language plpgsql
as $$
begin
  update public.workout_sessions
  set last_activity_at = now()
  where id = coalesce(new.workout_session_id, old.workout_session_id);
  return coalesce(new, old);
end;
$$;

create trigger session_exercises_touch_activity_trigger
  after insert or update or delete on public.workout_session_exercises
  for each row execute function public.touch_session_activity();

-- ============================================================
-- workout_sets: the highest-value trigger in this schema — every
-- set logged updates session volume/activity, checks for a new PR,
-- and rolls up exercise history. PRs and exercise_history are
-- intentionally NOT retroactively revoked on UPDATE/DELETE of a
-- set — matches user expectation that an achieved PR stays
-- achieved (same behavior as Strong/Hevy), not an oversight.
-- ============================================================
create or replace function public.handle_workout_set_change()
returns trigger
language plpgsql
as $$
declare
  v_session_id uuid;
begin
  select wse.workout_session_id into v_session_id
  from public.workout_session_exercises wse
  where wse.id = coalesce(new.workout_session_exercise_id, old.workout_session_exercise_id);

  update public.workout_sessions
  set total_volume_kg = public.calculate_workout_volume(v_session_id),
      last_activity_at = now()
  where id = v_session_id;

  if TG_OP in ('INSERT', 'UPDATE') and new.is_warmup = false then
    perform public.update_personal_record(new.id);
    perform public.update_exercise_history(new.id);
  end if;

  return coalesce(new, old);
end;
$$;

create trigger workout_set_change_trigger
  after insert or update or delete on public.workout_sets
  for each row execute function public.handle_workout_set_change();
