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
