-- Every table in this file is a cache. workout_sets (000005) is always
-- the source of truth; these exist purely so Dashboard/Statistics/
-- History reads don't have to aggregate the full sets history on every
-- request. All are kept current by triggers in 000010_triggers.sql
-- calling functions in 000009_functions.sql.

create table public.personal_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  record_type text not null check (record_type in ('max_weight', 'max_reps', 'max_volume', 'estimated_1rm')),
  value numeric not null check (value > 0),
  unit text not null default 'kg',
  workout_set_id uuid references public.workout_sets (id) on delete set null,
  achieved_at timestamptz not null default now(),
  unique (user_id, exercise_id, record_type)
);

create index personal_records_user_idx on public.personal_records (user_id);
create index personal_records_exercise_idx on public.personal_records (exercise_id);

-- Rollup of a user's history with one specific exercise — powers the
-- Exercise Detail screen's "your history with this exercise" panel
-- without scanning every past session.
create table public.exercise_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  times_performed integer not null default 0 check (times_performed >= 0),
  last_performed_at timestamptz,
  best_weight_kg numeric check (best_weight_kg is null or best_weight_kg > 0),
  best_reps integer check (best_reps is null or best_reps > 0),
  best_volume_kg numeric check (best_volume_kg is null or best_volume_kg > 0),
  updated_at timestamptz not null default now(),
  unique (user_id, exercise_id)
);

create index exercise_history_user_idx on public.exercise_history (user_id, last_performed_at desc);
create index exercise_history_exercise_idx on public.exercise_history (exercise_id);

-- Pre-aggregated period statistics (week/month/all-time) — the
-- Statistics screen's volume-trend chart and consistency numbers read
-- from here, never from a live aggregation over months of sets.
create table public.statistics_cache (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  period_type text not null check (period_type in ('week', 'month', 'all_time')),
  period_start date not null,
  total_workouts integer not null default 0 check (total_workouts >= 0),
  total_volume_kg numeric not null default 0 check (total_volume_kg >= 0),
  total_sets integer not null default 0 check (total_sets >= 0),
  total_duration_seconds integer not null default 0 check (total_duration_seconds >= 0),
  muscle_group_distribution jsonb not null default '{}'::jsonb,
  computed_at timestamptz not null default now(),
  unique (user_id, period_type, period_start)
);

create index statistics_cache_user_period_idx on public.statistics_cache (user_id, period_type, period_start desc);

-- Single row per user — the numbers the Dashboard needs on every app
-- open (streak, this week's count). One indexed row read instead of
-- several aggregation queries every time the app launches.
create table public.dashboard_cache (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  current_streak_days integer not null default 0 check (current_streak_days >= 0),
  longest_streak_days integer not null default 0 check (longest_streak_days >= 0),
  workouts_this_week integer not null default 0 check (workouts_this_week >= 0),
  last_workout_at timestamptz,
  computed_at timestamptz not null default now()
);
