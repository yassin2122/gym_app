create table public.workout_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  name text not null,
  description text,
  category text check (category in ('push_pull_legs', 'upper_lower', 'full_body', 'custom')),
  is_public boolean not null default false,
  estimated_duration_minutes integer check (estimated_duration_minutes is null or estimated_duration_minutes > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- A template is either a system template (user_id null, always
  -- effectively public) or a user-owned one — is_public only means
  -- something for a user-owned template. Prevents an ambiguous state
  -- where a system template is marked private.
  check (user_id is not null or is_public = true)
);

create index workout_templates_user_idx on public.workout_templates (user_id);
create index workout_templates_category_idx on public.workout_templates (category);
create index workout_templates_public_idx on public.workout_templates (is_public) where is_public = true;

create table public.template_exercises (
  id uuid primary key default gen_random_uuid(),
  workout_template_id uuid not null references public.workout_templates (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  order_index integer not null,
  target_sets integer check (target_sets is null or target_sets > 0),
  target_reps_min integer check (target_reps_min is null or target_reps_min > 0),
  target_reps_max integer check (target_reps_max is null or target_reps_max >= target_reps_min),
  target_rpe numeric check (target_rpe is null or (target_rpe >= 0 and target_rpe <= 10)),
  rest_seconds integer check (rest_seconds is null or rest_seconds > 0),
  notes text,
  unique (workout_template_id, order_index)
);

create index template_exercises_template_idx on public.template_exercises (workout_template_id, order_index);

-- Exercise favorites. Deliberately scoped to exercises only (not
-- templates/workouts) — that's the actual requested use case and the
-- one every reviewed competitor app (Hevy, Strong) surfaces; adding a
-- polymorphic favorites table for hypothetical future favoritable types
-- would be exactly the premature generalization the brief warns against.
create table public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, exercise_id)
);

create index favorites_user_idx on public.favorites (user_id, created_at desc);

-- Deferred FK from 000005_workouts.sql, now that workout_templates exists.
alter table public.workout_sessions
  add constraint workout_sessions_template_fk
  foreign key (workout_template_id) references public.workout_templates (id) on delete set null;
