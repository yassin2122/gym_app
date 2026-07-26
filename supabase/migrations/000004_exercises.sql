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
