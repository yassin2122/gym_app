-- ==========================================
-- MIGRATION: 000001_extensions.sql
-- ==========================================
-- Extensions used throughout this schema.
--
-- pgcrypto:   gen_random_uuid() for every table's primary key default.
-- pg_trgm:    trigram similarity indexes for fuzzy/typo-tolerant search
--             on exercise names and aliases.
-- unaccent:   strips accents in search input ("bíceps" matches "biceps")
--             — cheap to add now, meaningfully improves search recall
--             for a dataset with international exercise names.
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists unaccent;


-- ==========================================
-- MIGRATION: 000002_profiles.sql
-- ==========================================
-- Design note: this schema deliberately has NO `public.users` table.
-- Supabase's `auth.users` already IS the users table — creating a
-- second one duplicates identity and is a common anti-pattern. Every
-- reference to "the user" elsewhere in this schema is a foreign key to
-- `public.profiles.id`, which is itself a 1:1 extension of `auth.users`.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique,
  display_name text,
  avatar_url text,
  is_guest boolean not null default false,
  date_of_birth date,
  gender text check (gender in ('male', 'female', 'other', 'prefer_not_to_say')),
  height_cm numeric check (height_cm is null or height_cm > 0),
  experience_level text check (experience_level in ('beginner', 'intermediate', 'advanced')),
  primary_goal text check (primary_goal in ('build_muscle', 'lose_weight', 'improve_strength', 'improve_endurance', 'general_fitness')),
  unit_preference text not null default 'metric' check (unit_preference in ('metric', 'imperial')),
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'App-specific profile data, 1:1 with auth.users. This is "the users table" for every other FK in this schema — see the design note above for why there is no separate public.users.';

create index profiles_username_idx on public.profiles (username) where username is not null;

-- One row per user, holding app behavior settings rather than identity.
-- Split from `profiles` because these change far more often via a
-- Settings screen and have a completely different access pattern (one
-- row read on app start, occasionally updated) than identity data.
create table public.user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles (id) on delete cascade,
  rest_timer_default_seconds integer not null default 90 check (rest_timer_default_seconds > 0),
  rest_timer_sound_enabled boolean not null default true,
  haptics_enabled boolean not null default true,
  notifications_enabled boolean not null default true,
  weekly_workout_goal integer check (weekly_workout_goal is null or weekly_workout_goal between 1 and 14),
  week_start_day smallint not null default 1 check (week_start_day between 0 and 6), -- 0=Sunday
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.user_preferences is
  'App behavior settings, split from profiles because it changes independently and has a different read pattern (fetched once per session, not joined into every user-facing query).';

-- Point-in-time body measurements. Separate from weight_history because
-- these are logged far less frequently (weekly/monthly vs. daily) and
-- have a completely different shape (many optional measurement fields
-- vs. a single required weight value) — one flexible table for both
-- would mean nullable columns dominating either use case.
create table public.body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  measured_at date not null default current_date,
  chest_cm numeric check (chest_cm is null or chest_cm > 0),
  waist_cm numeric check (waist_cm is null or waist_cm > 0),
  hips_cm numeric check (hips_cm is null or hips_cm > 0),
  bicep_cm numeric check (bicep_cm is null or bicep_cm > 0),
  thigh_cm numeric check (thigh_cm is null or thigh_cm > 0),
  calf_cm numeric check (calf_cm is null or calf_cm > 0),
  neck_cm numeric check (neck_cm is null or neck_cm > 0),
  body_fat_percentage numeric check (body_fat_percentage is null or body_fat_percentage between 0 and 100),
  notes text,
  created_at timestamptz not null default now()
);

create index body_measurements_user_date_idx on public.body_measurements (user_id, measured_at desc);

-- High-frequency weight log — the Dashboard body weight graph's source.
create table public.weight_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  weight_kg numeric not null check (weight_kg > 0),
  logged_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now()
);

create index weight_history_user_logged_idx on public.weight_history (user_id, logged_at desc);

-- Auto-create a profile row whenever a new auth.users row appears
-- (covers real sign-up and anonymous/guest sign-in). Uses dynamic
-- (to_jsonb) extraction of is_anonymous rather than static field access
-- — see the original Sprint 1 hardening notes in DATABASE.md for why:
-- a static NEW.is_anonymous reference breaks account creation entirely
-- on any Supabase/GoTrue schema variant where that column is absent.
create function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, is_guest)
  values (
    new.id,
    coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false)
  );
  insert into public.user_preferences (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();


-- ==========================================
-- MIGRATION: 000003_reference_tables.sql
-- ==========================================
-- Reference/lookup tables. Kept as real tables (not a CHECK-constrained
-- text enum) because each carries metadata beyond a name (body_region,
-- equipment category, display ordering) and because new values
-- (a new equipment type, a new muscle) should be an INSERT, not a
-- migration — exactly the kind of change that shouldn't require a
-- schema change, per the "none of this should need redesign later"
-- brief.

create table public.muscle_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  body_region text not null check (body_region in ('upper_body', 'lower_body', 'core', 'full_body')),
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  equipment_category text not null check (
    equipment_category in ('free_weight', 'machine', 'cable', 'bodyweight', 'accessory', 'cardio_machine')
  ),
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.exercise_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- Free-form, many-to-many tags — distinct from the rigid categories
-- above. Categories are a controlled taxonomy (one per exercise,
-- curated); tags are open-ended (many per exercise, can grow without
-- curation review) — e.g. "home-friendly", "compound", "unilateral".
create table public.exercise_tags (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create index muscle_groups_body_region_idx on public.muscle_groups (body_region);
create index equipment_category_idx on public.equipment (equipment_category);


-- ==========================================
-- MIGRATION: 000004_exercises.sql
-- ==========================================
create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text,
  category_id uuid references public.exercise_categories (id),

  -- Broad classification, denormalized from category for fast filtering
  -- without a join on the single most common filter (Exercise Library's
  -- top-level type tabs). Kept in sync by a trigger when category_id
  -- changes — see 000010_triggers.sql.
  exercise_type text not null check (exercise_type in ('strength', 'cardio', 'mobility', 'calisthenics')),

  movement_pattern text check (
    movement_pattern in ('push', 'pull', 'squat', 'hinge', 'lunge', 'carry', 'rotation', 'isometric', 'other')
  ),
  mechanics text check (mechanics in ('compound', 'isolation')),
  force text check (force in ('push', 'pull', 'static')),
  difficulty text check (difficulty in ('beginner', 'intermediate', 'advanced')),

  -- Denormalized from the exercise's primary muscle's body_region for
  -- the same reason as exercise_type — body region is a top-level
  -- Exercise Library filter and shouldn't require a join to every list
  -- query. Kept in sync by trigger when exercise_muscles changes.
  body_region text check (body_region in ('upper_body', 'lower_body', 'core', 'full_body')),

  instructions text[] not null default '{}',
  common_mistakes text[] not null default '{}',
  tips text[] not null default '{}',

  popularity integer not null default 0 check (popularity >= 0),
  estimated_duration_seconds integer check (estimated_duration_seconds is null or estimated_duration_seconds > 0),
  calorie_multiplier numeric check (calorie_multiplier is null or calorie_multiplier > 0),

  is_custom boolean not null default false,
  created_by uuid references public.profiles (id) on delete set null,

  -- Maintained by trigger (see 000010_triggers.sql), not a generated
  -- column — it needs to incorporate muscle/equipment names from
  -- related tables, which a single-table GENERATED ALWAYS AS column
  -- cannot reference.
  search_vector tsvector,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.exercises is
  'The exercise library. exercise_type and body_region are intentionally denormalized from category/exercise_muscles for fast top-level filtering — see inline comments. Seeded from the free-exercise-db public domain dataset; see exercise_import/ for the pipeline.';

create index exercises_category_idx on public.exercises (category_id);
create index exercises_exercise_type_idx on public.exercises (exercise_type);
create index exercises_body_region_idx on public.exercises (body_region);
create index exercises_difficulty_idx on public.exercises (difficulty);
create index exercises_search_vector_idx on public.exercises using gin (search_vector);
create index exercises_name_trgm_idx on public.exercises using gin (name gin_trgm_ops);

-- Alternate names a user might search for (e.g. "chin-up" as an alias
-- for "pull-up"). Not populated from free-exercise-db this pass — that
-- dataset doesn't provide aliases — schema is ready for curation.
create table public.exercise_aliases (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  alias text not null,
  unique (exercise_id, alias)
);
create index exercise_aliases_alias_trgm_idx on public.exercise_aliases using gin (alias gin_trgm_ops);

create table public.exercise_images (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  url text not null,
  display_order integer not null default 0,
  created_at timestamptz not null default now()
);
create index exercise_images_exercise_idx on public.exercise_images (exercise_id, display_order);

create table public.exercise_videos (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  url text not null,
  video_type text not null default 'demonstration' check (video_type in ('demonstration', 'tutorial')),
  created_at timestamptz not null default now()
);

-- Many-to-many: an exercise has a primary muscle, secondary muscles, and
-- stabilizers. Junction table with a role column rather than three
-- separate array columns — a proper relational model that supports
-- "find all exercises where quadriceps is a stabilizer" without any
-- array-contains gymnastics, and keeps muscle_groups as the single
-- source of truth for a muscle's metadata.
create table public.exercise_muscles (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  muscle_group_id uuid not null references public.muscle_groups (id),
  role text not null check (role in ('primary', 'secondary', 'stabilizer')),
  unique (exercise_id, muscle_group_id, role)
);
create index exercise_muscles_exercise_idx on public.exercise_muscles (exercise_id);
create index exercise_muscles_muscle_role_idx on public.exercise_muscles (muscle_group_id, role);

create table public.exercise_equipment (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  equipment_id uuid not null references public.equipment (id),
  is_required boolean not null default true,
  unique (exercise_id, equipment_id)
);
create index exercise_equipment_exercise_idx on public.exercise_equipment (exercise_id);
create index exercise_equipment_equipment_idx on public.exercise_equipment (equipment_id);

create table public.exercise_tag_map (
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  tag_id uuid not null references public.exercise_tags (id) on delete cascade,
  primary key (exercise_id, tag_id)
);

-- Not populated from free-exercise-db this pass (no relationship data in
-- that dataset) — schema is ready, population is a future curation task.
create table public.exercise_progressions (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  progression_exercise_id uuid not null references public.exercises (id) on delete cascade,
  check (exercise_id <> progression_exercise_id),
  unique (exercise_id, progression_exercise_id)
);

create table public.exercise_regressions (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  regression_exercise_id uuid not null references public.exercises (id) on delete cascade,
  check (exercise_id <> regression_exercise_id),
  unique (exercise_id, regression_exercise_id)
);

create table public.exercise_alternatives (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  alternative_exercise_id uuid not null references public.exercises (id) on delete cascade,
  reason text check (reason in ('equipment_substitute', 'injury_substitute', 'difficulty_substitute')),
  check (exercise_id <> alternative_exercise_id),
  unique (exercise_id, alternative_exercise_id)
);


-- ==========================================
-- MIGRATION: 000005_workouts.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000006_templates.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000007_statistics.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000008_views.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000009_functions.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000010_triggers.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000011_policies.sql
-- ==========================================
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


-- ==========================================
-- MIGRATION: 000012_sync_and_settings.sql
-- ==========================================
-- Offline sync queue — supports the local-first workout session flow
-- described in the original docs/SYNC.md (mobile queues writes locally,
-- pushes when connectivity returns). This table is the server-side
-- record of what was synced and when, useful for conflict debugging and
-- multi-device awareness; the mobile client's local queue itself lives
-- on-device, not here.
create table public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  entity_type text not null check (entity_type in ('workout_session', 'workout_session_exercise', 'workout_set', 'weight_history', 'body_measurement')),
  entity_id uuid not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  payload jsonb,
  status text not null default 'pending' check (status in ('pending', 'synced', 'failed')),
  error_message text,
  created_at timestamptz not null default now(),
  synced_at timestamptz
);

create index sync_queue_user_status_idx on public.sync_queue (user_id, status);

alter table public.sync_queue enable row level security;
create policy "sync_queue_select_own" on public.sync_queue for select using (auth.uid() = user_id);
create policy "sync_queue_insert_own" on public.sync_queue for insert with check (auth.uid() = user_id);
create policy "sync_queue_update_own" on public.sync_queue for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "sync_queue_delete_own" on public.sync_queue for delete using (auth.uid() = user_id);

-- Global app configuration — feature flags, minimum supported app
-- version, maintenance-mode flags. Not user data; a single shared table
-- the whole app reads on startup.
create table public.app_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
create policy "app_settings_select_all" on public.app_settings for select using (auth.role() = 'authenticated');
create policy "app_settings_service_write" on public.app_settings for all
  using (auth.role() = 'service_role') with check (auth.role() = 'service_role');


-- ==========================================
-- MIGRATION: 000013_grants.sql
-- ==========================================
-- RLS policies (000011) restrict WHICH rows a role can touch — but
-- Postgres separately requires table-level GRANTs before RLS is even
-- evaluated. Supabase's platform pre-configures default privileges so
-- new tables automatically grant to anon/authenticated/service_role,
-- which is why this migration is easy to forget is even necessary — but
-- a "ready to apply with minimal manual work" deliverable shouldn't
-- depend on an implicit, undocumented-in-this-repo platform behavior.
-- Explicit grants here mean this schema is correct even if applied
-- somewhere that behaves differently (e.g. a self-hosted Supabase
-- instance with different default privilege configuration).

grant usage on schema public to authenticated, anon, service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant all on all tables in schema public to service_role;

grant usage, select on all sequences in schema public to authenticated, service_role;

grant execute on all functions in schema public to authenticated, service_role;

-- Ensures tables created by FUTURE migrations also get these grants
-- automatically, without needing another grants migration each time.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant select on tables to anon;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant execute on functions to authenticated, service_role;


