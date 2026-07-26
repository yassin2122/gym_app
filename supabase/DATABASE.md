# DATABASE.md — Gym App Production Schema

Status: production schema, verified end-to-end against a real local
Postgres instance (all 13 migrations + seed + full workout flow +
RLS cross-user isolation — see "Verification" at the bottom for exactly
what was tested and what bugs that testing caught before this was
written).

This supersedes the earlier MVP schema. No `public.users` table exists
— see "Identity" below for why.

---

## Entity relationship overview

```
auth.users (Supabase-managed)
  └─1:1─ profiles ──1:1── user_preferences
       │
       ├─1:N─ body_measurements
       ├─1:N─ weight_history
       ├─1:N─ favorites ──N:1── exercises
       ├─1:N─ workout_templates ──1:N── template_exercises ──N:1── exercises
       ├─1:N─ workout_sessions ──N:1── workout_templates (optional)
       │         └─1:N─ workout_session_exercises ──N:1── exercises
       │                   └─1:N─ workout_sets
       ├─1:N─ personal_records ──N:1── exercises
       ├─1:N─ exercise_history ──N:1── exercises
       ├─1:N─ statistics_cache
       ├─1:1─ dashboard_cache
       └─1:N─ sync_queue

exercises
  ├─N:1─ exercise_categories
  ├─1:N─ exercise_aliases
  ├─1:N─ exercise_images
  ├─1:N─ exercise_videos
  ├─N:M─ muscle_groups (via exercise_muscles, with role: primary/secondary/stabilizer)
  ├─N:M─ equipment (via exercise_equipment)
  ├─N:M─ exercise_tags (via exercise_tag_map)
  ├─N:M─ exercises (via exercise_progressions/regressions/alternatives — self-referential)
```

## Identity: why there is no `public.users` table

Supabase's `auth.users` already is the users table. A separate
`public.users` would duplicate identity and invite drift between the
two. Every "the user" reference in this schema is a foreign key to
`public.profiles.id`, which is a 1:1 extension of `auth.users.id`,
auto-created by a trigger on `auth.users` insert (covers both real
sign-up and anonymous/guest sign-in).

---

## Tables

### Identity & personal data
| Table | Purpose |
|---|---|
| `profiles` | 1:1 extension of `auth.users` — display name, physical stats, goals |
| `user_preferences` | App behavior settings, split from `profiles` because it changes independently (Settings screen) and has a different read pattern |
| `body_measurements` | Periodic body measurements (chest/waist/etc.) — separate from `weight_history` because it's logged far less often and has a different shape |
| `weight_history` | High-frequency weight log — Dashboard's body weight graph |

### Reference/taxonomy
| Table | Purpose |
|---|---|
| `muscle_groups` | Real tables, not enums — new values are an INSERT, not a migration |
| `equipment` | Same rationale |
| `exercise_categories` | Controlled taxonomy, one per exercise |
| `exercise_tags` | Open-ended, many-per-exercise, no curation review needed to add one |

### Exercise library
| Table | Purpose |
|---|---|
| `exercises` | The library itself. `exercise_type` and `body_region` are **denormalized** from category/primary-muscle for fast top-level filtering — see the "Denormalization" section below for why this is justified rather than premature |
| `exercise_aliases` | Alternate search terms (schema ready, not populated this pass — source dataset has none) |
| `exercise_images` / `exercise_videos` | Media, ordered, many per exercise |
| `exercise_muscles` | N:M junction with a `role` column (primary/secondary/stabilizer) — proper relational model instead of three array columns |
| `exercise_equipment` | N:M junction |
| `exercise_tag_map` | N:M junction for free-form tags |
| `exercise_progressions` / `exercise_regressions` / `exercise_alternatives` | Self-referential relationships (schema ready, not populated — source dataset has no relationship data; future curation task) |

### Workout tracking (the highest-write-volume tables)
| Table | Purpose |
|---|---|
| `workout_sessions` | One row per performed/in-progress workout. `total_volume_kg` is a maintained cache; `last_activity_at` drives resume/stale-session detection and offline sync conflict resolution |
| `workout_session_exercises` | Exercises actually performed — may diverge from the originating template (added/removed/skipped) |
| `workout_sets` | The atomic unit of logged performance — the source of truth every cache below is computed from |

### Templates & favorites
| Table | Purpose |
|---|---|
| `workout_templates` | System (user_id null) or user-owned routines |
| `template_exercises` | Ordered exercises within a template, with targets |
| `favorites` | Exercise favorites (scoped to exercises only — see inline comment in the migration for why a polymorphic favorites table was deliberately not built) |

### Caches (all maintained by triggers, all read-only to users via RLS)
| Table | Purpose |
|---|---|
| `personal_records` | Best result per user/exercise/record_type (max_weight, max_reps, max_volume, estimated_1rm) |
| `exercise_history` | Per-user-per-exercise rollup (times performed, last performed, bests) — powers "your history with this exercise" |
| `statistics_cache` | Pre-aggregated week/month/all-time stats, including muscle group distribution |
| `dashboard_cache` | Single row per user — streaks, this-week count, last workout |

### Sync & config
| Table | Purpose |
|---|---|
| `sync_queue` | Server-side record of offline-originated writes, for conflict debugging and multi-device awareness (the mobile client's own local queue lives on-device — see the original `SYNC.md` offline strategy) |
| `app_settings` | Global config (feature flags, min app version) — not user data |

---

## Denormalization — justified, not premature

Two columns break normalization deliberately:
- `exercises.exercise_type` (copy of the category's broad classification)
- `exercises.body_region` (copy of the primary muscle's body region)

Both are the single most common top-level filter in the Exercise Library
UI. Without denormalizing, every list query would need a join through
`exercise_categories` or `exercise_muscles` just to filter — for data
that essentially never changes per exercise. Both are kept in sync by
triggers (`sync_exercise_body_region_trigger`, `sync_exercise_type_trigger`)
so the denormalization can never drift from the true relational data.
Every other relationship in this schema (muscles, equipment, tags,
progressions) stays properly normalized — this isn't a general pattern,
it's two specific, justified exceptions.

---

## Indexes

| Table | Index | Reason |
|---|---|---|
| `exercises` | GIN on `search_vector` | Full text search — the primary Exercise Library query |
| `exercises` | GIN trigram on `name` | Fuzzy/typo-tolerant fallback search |
| `exercises` | `category_id`, `exercise_type`, `body_region`, `difficulty` | Top-level filters |
| `exercise_aliases` | GIN trigram on `alias` | Alias search |
| `exercise_muscles` | `(muscle_group_id, role)` | "All primary chest exercises" queries |
| `workout_sessions` | `(user_id, started_at desc)`, `(user_id, status)`, `(user_id, last_activity_at desc)` | History sort, resume-session lookup, sync conflict resolution |
| `workout_session_exercises` | `(workout_session_id, order_index)` | Ordered render of one session's exercises |
| `workout_sets` | `(workout_session_exercise_id, set_number)` | The hottest read/write path during an active workout |
| `personal_records` | `user_id`, `exercise_id` | Dashboard PR card, exercise detail history |
| `statistics_cache` | `(user_id, period_type, period_start desc)` | Statistics screen |
| `weight_history` / `body_measurements` | `(user_id, date desc)` | Trend graphs |
| `favorites` | `(user_id, created_at desc)` | Favorites list |

---

## Row Level Security

Every table has RLS enabled. Three patterns, applied consistently:

1. **Owner-only** (profiles, weight_history, workout_sessions, favorites,
   etc.): `auth.uid() = user_id` on SELECT, and — critically — **every
   UPDATE policy has a matching `WITH CHECK`, not just `USING`**.
   `USING` alone only gates which existing rows can be targeted; without
   `WITH CHECK` a user could rewrite their own row's `user_id` to point
   at someone else, silently transferring or forging data. This pattern
   was learned the hard way in this project's Sprint 1 security
   hardening pass and is now applied everywhere from the start rather
   than retrofitted.
2. **Shared read-only reference data** (exercises and everything under
   it, muscle_groups, equipment, exercise_categories): readable by any
   `authenticated` role (this includes Supabase guest/anonymous
   sessions — they carry the `authenticated` Postgres role, distinguished
   by the `is_anonymous` JWT claim, not a different role), writable only
   by `service_role`.
3. **Caches** (personal_records, exercise_history, statistics_cache,
   dashboard_cache): **SELECT-only for users, no INSERT/UPDATE policy at
   all**. The only way these tables get written is through the
   `SECURITY DEFINER` functions called by triggers — RLS itself is what
   enforces "this is a cache, not user-editable data," not just a code
   convention.

**Table-level GRANTs** (migration `000013`) are explicit rather than
relying on Supabase's implicit default-privilege behavior — see that
migration's comment for why a "ready to apply anywhere" deliverable
shouldn't depend on an assumption about platform defaults.

**Views** are all declared `security_invoker = true` — without this, a
Postgres view runs with the view owner's privileges by default, silently
bypassing RLS on the underlying tables. This is called out explicitly in
`000008_views.sql` because it's a real, easy-to-miss security bug, not a
style choice.

---

## Functions

| Function | Purpose | Security |
|---|---|---|
| `calculate_workout_volume(session_id)` | Sums weight×reps for non-warmup sets | invoker |
| `update_personal_record(set_id)` | Checks a logged set against current PRs (max_weight, max_reps, max_volume, estimated_1rm via the Epley formula), upserts if beaten | **definer** |
| `update_exercise_history(set_id)` | Rolls up a user's cumulative stats for one exercise | **definer** |
| `update_statistics(user_id)` | Recomputes week/month/all-time aggregates | **definer** |
| `dashboard_summary(user_id)` | Recomputes streaks and this-week count | **definer** |
| `exercise_search(query, limit, offset)` | Full text + trigram ranked search | invoker |
| `recent_workouts(user_id, limit)` | RPC convenience wrapper over `history_view` | invoker |
| `favorite_toggle(user_id, exercise_id)` | Adds/removes a favorite, returns the new state | invoker |
| `session_summary(session_id)` | Single-row workout summary (for a "finished!" screen) | invoker |
| `history_summary(user_id, limit, offset)` | Paginated wrapper over `history_view` | invoker |

Functions marked **definer** run as the function owner regardless of
caller — this is what lets a normal user's set-logging action update a
cache table their own RLS policy says they can't directly write to. This
is intentional and is the enforcement mechanism described in the RLS
section above, not a bypass of it.

---

## Triggers

| Trigger | Fires on | Effect |
|---|---|---|
| `set_*_updated_at` | BEFORE UPDATE on profiles, user_preferences, exercises, workout_templates | Maintains `updated_at` |
| `exercise_search_base_trigger` | BEFORE INSERT/UPDATE of name/description/instructions on exercises | Rebuilds `search_vector`'s base text |
| `exercise_muscles_search_trigger` / `exercise_equipment_search_trigger` | AFTER INSERT on the junction tables | Incrementally folds muscle/equipment names into `search_vector` |
| `sync_exercise_body_region_trigger` | AFTER INSERT on exercise_muscles (primary role) | Keeps `exercises.body_region` in sync |
| `sync_exercise_type_trigger` | BEFORE UPDATE of category_id on exercises | Keeps `exercises.exercise_type` in sync on edit |
| `workout_session_completion_trigger` | BEFORE UPDATE on workout_sessions | Auto-sets `completed_at`/`duration_seconds` when status becomes 'completed' |
| `workout_session_completed_after_trigger` | AFTER UPDATE on workout_sessions | Calls `update_statistics` + `dashboard_summary` |
| `session_exercises_touch_activity_trigger` | AFTER INSERT/UPDATE/DELETE on workout_session_exercises | Touches the parent session's `last_activity_at` |
| `workout_set_change_trigger` | AFTER INSERT/UPDATE/DELETE on workout_sets | Recomputes session volume + activity, checks PRs, rolls up exercise history |

**Deliberate design choice:** PRs and exercise_history are **not**
retroactively revoked when a set is edited down or deleted — matches
user expectation that an achieved PR stays achieved (the same behavior
as Strong/Hevy), not an oversight.

---

## Views

All declared `security_invoker = true` (see RLS section). `dashboard_view`,
`history_view`, `exercise_history_view`, `personal_records_view`,
`statistics_view`, `favorite_exercises_view` — one join-friendly read
shape per major screen, so the mobile client's data layer issues one
query instead of assembling several client-side.

---

## Query examples

```sql
-- Exercise Library: search + filter
select * from exercise_search('bench press', 30, 0);

-- Dashboard, one query
select * from dashboard_view where user_id = auth.uid();

-- History, paginated
select * from history_summary(auth.uid(), 20, 0);

-- Toggle a favorite
select favorite_toggle(auth.uid(), '<exercise_id>');
```

---

## Performance notes

- `workout_sets` is the fastest-growing table by a wide margin. No
  partitioning yet — not needed at expected launch scale, but if this
  reaches Hevy/Strong-scale usage (millions of sets), partition by month
  or by user_id range before it becomes a problem, not after.
- `exercise_search`'s trigram fallback (`e.name % query`) is O(exercise
  count) in the worst case but the GIN trigram index keeps this fast up
  to tens of thousands of exercises — well beyond any realistic library
  size.
- Cache tables (`statistics_cache`, `dashboard_cache`, `personal_records`,
  `exercise_history`) exist specifically so Dashboard/Statistics/History
  reads never aggregate raw `workout_sets` — this is the single biggest
  read-performance decision in this schema.

## Future scalability notes

- **AI Coach**: would read from `workout_sets`/`exercise_history` (already
  structured for aggregation) and likely add its own
  `ai_recommendations` table — no changes needed here.
- **Apple Health / Google Fit / wearables**: would add an
  `external_sync_sources` table plus source-tagging columns on
  `weight_history`/`workout_sessions` — additive, not a redesign.
- **Premium features**: would need an `entitlements`/`subscriptions`
  table keyed to `profiles.id` — additive.
- **User-created exercises**: `exercises.is_custom`/`created_by` already
  exist; the only real work is a second RLS branch
  (`created_by = auth.uid()`) on the INSERT/UPDATE policies, not a
  schema change.

---

## Verification

This schema was applied end-to-end against a real local Postgres 16
instance (not just read for syntax) as part of producing this document:

1. All 13 migrations applied cleanly to a fresh database, in order.
2. The generated seed (`02_exercise_library.sql`, 351 exercises) applied
   cleanly — **after the validator's live URL check caught a wrong image
   base URL, and a first seed run caught a real SQL-generation bug**
   (array literals used double quotes instead of single quotes) — both
   fixed and re-verified, not just fixed on paper.
3. A full workout flow was simulated as a real authenticated user: start
   session → log two sets → verified session volume, all four PR types,
   and exercise_history rolled up correctly → completed the session →
   verified auto-computed duration and `dashboard_cache`/`statistics_cache`.
   **This caught two more real bugs**: an overly strict `duration_seconds
   > 0` constraint that rejected a same-second completion, and a join
   fan-out bug in `update_statistics` that was double-counting volume —
   both fixed and re-verified with a clean rebuild.
4. RLS cross-user isolation was tested directly: a second simulated user
   was confirmed unable to see the first user's sessions or personal
   records.
5. Views and `favorite_toggle` were exercised directly and returned
   correct joined data.

Four real bugs were found and fixed by this process before delivery.
That's the actual value of testing against a real database instead of
reviewing SQL by eye — noted here so it's clear this wasn't just
"generate and hope."
