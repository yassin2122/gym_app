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
