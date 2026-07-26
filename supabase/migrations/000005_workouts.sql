create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,

  -- FK constraint added in 000006_templates.sql once workout_templates
  -- exists — a forward reference, handled the standard way rather than
  -- reordering migrations away from the requested numbering scheme.
  workout_template_id uuid,

  name text not null,
  status text not null default 'in_progress' check (status in ('in_progress', 'completed', 'abandoned')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  last_activity_at timestamptz not null default now(),
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),

  -- Cached, maintained by trigger on workout_sets changes (see
  -- 000010_triggers.sql) — avoids summing every set on every History/
  -- Dashboard read. See calculate_workout_volume() in 000009_functions.sql
  -- for the calculation this trigger calls.
  total_volume_kg numeric not null default 0 check (total_volume_kg >= 0),

  notes text,
  created_at timestamptz not null default now(),

  check (status <> 'completed' or completed_at is not null),
  check (completed_at is null or completed_at >= started_at)
);

comment on table public.workout_sessions is
  'One row per performed (or in-progress) workout. last_activity_at drives resume/stale-session detection and offline sync conflict resolution (last-write-wins). total_volume_kg is a maintained cache, not authoritative — workout_sets is the source of truth.';

create index workout_sessions_user_started_idx on public.workout_sessions (user_id, started_at desc);
create index workout_sessions_user_status_idx on public.workout_sessions (user_id, status);
create index workout_sessions_user_activity_idx on public.workout_sessions (user_id, last_activity_at desc);
create index workout_sessions_template_idx on public.workout_sessions (workout_template_id);

create table public.workout_session_exercises (
  id uuid primary key default gen_random_uuid(),
  workout_session_id uuid not null references public.workout_sessions (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  order_index integer not null,
  status text not null default 'completed' check (status in ('completed', 'skipped', 'removed')),
  notes text,
  created_at timestamptz not null default now(),
  unique (workout_session_id, order_index)
);

create index workout_session_exercises_session_idx on public.workout_session_exercises (workout_session_id, order_index);
create index workout_session_exercises_exercise_idx on public.workout_session_exercises (exercise_id);

create table public.workout_sets (
  id uuid primary key default gen_random_uuid(),
  workout_session_exercise_id uuid not null references public.workout_session_exercises (id) on delete cascade,
  set_number integer not null,
  weight_kg numeric check (weight_kg is null or weight_kg > 0),
  reps integer not null check (reps > 0),
  rpe numeric check (rpe is null or (rpe >= 0 and rpe <= 10)),
  is_warmup boolean not null default false,
  completed_at timestamptz not null default now(),
  unique (workout_session_exercise_id, set_number)
);

create index workout_sets_session_exercise_idx on public.workout_sets (workout_session_exercise_id, set_number);

comment on table public.workout_sets is
  'The atomic unit of logged performance. Every derived statistic (personal_records, statistics_cache, exercise_history) is computable from this table — it is the ground truth if any cache ever needs to be rebuilt.';
