# Supabase — Gym App Production Backend

Full production schema. See `DATABASE.md` for the complete design
documentation, including what was actually verified before delivery.

## Structure

```
supabase/
  migrations/        13 migrations, applied in filename order
  seed/               02_exercise_library.sql — generated, do not hand-edit
                      (reference data for muscle_groups/equipment/
                      exercise_categories is included in this same file,
                      generated alongside the exercises that use it)
  exercise_import/    the pipeline that produced 02_exercise_library.sql
    raw/              the fetched free-exercise-db dataset
    transformer/      maps raw data onto this schema's taxonomy
    validator/        checks constraints + live-verifies a sample of image URLs
    importer/         generates the final idempotent seed SQL
  functions/          (see note below)
  triggers/           (see note below)
  views/              (see note below)
  policies/           (see note below)
  DATABASE.md
  README.md
```

**Note on functions/triggers/views/policies folders:** the actual,
applied SQL for these lives in the numbered migrations
(`000008_views.sql`, `000009_functions.sql`, `000010_triggers.sql`,
`000011_policies.sql`) — migrations are the single source of truth that
`supabase db push` actually runs. These folders are kept as empty
placeholders matching the requested output structure; duplicating the
same SQL in two places would create a real risk of the copies drifting
out of sync, which is worse than not having the convenience copy.

## Running

```bash
supabase init          # if not already a linked project
supabase start          # local Postgres + Auth + Storage
supabase db reset       # applies all migrations, then seed/
```

Against a hosted project:
```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
psql "$DATABASE_URL" -f seed/02_exercise_library.sql
```

## Regenerating the exercise library

```bash
cd exercise_import/transformer && python3 transform.py
cd ../validator && python3 validate.py
cd ../importer && python3 generate_sql.py
```

Each stage writes its output for the next to read
(`normalized_exercises.json` → `validated_exercises.json` →
`../../seed/02_exercise_library.sql`). The validator will hard-fail
(non-zero exit) on a schema violation or if sampled image URLs don't
resolve — it's meant to be a real gate, not a formality.

## What's real vs. what's schema-ready-but-empty

**Populated from real data (free-exercise-db, public domain):**
exercises, exercise_images, exercise_muscles, exercise_equipment,
exercise_categories, muscle_groups, equipment.

**Schema-ready, deliberately not populated** (the source dataset has no
data for these — populating them would mean fabricating it):
exercise_aliases, exercise_progressions, exercise_regressions,
exercise_alternatives, exercise_tags/exercise_tag_map.

**Known coverage gap:** the `cardio` category has only 1 exercise with
complete metadata in the source dataset (out of 14 raw cardio entries —
most are missing force/mechanic/level). Worth supplementing from a
dedicated cardio-focused dataset before this ships if cardio tracking is
a priority feature.

## Superseded

This replaces the earlier MVP-scoped schema (13 smaller migrations
covering a subset of these tables). This is not an incremental upgrade
path from that schema — it's a fresh design for a new Supabase project,
per the brief. Do not attempt to apply both migration sets to the same
database.
