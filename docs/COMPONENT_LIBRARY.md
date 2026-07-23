# Component Library — Gym App

Status: MVP design reference. The canonical registry of every reusable UI
widget in the app. Any screen needing a control not listed here adds it
to this document (and to `core/widgets/` or the owning feature's
`presentation/widgets/`) before using it — no one-off, screen-local
widgets for anything that could plausibly be reused.

Location convention: components used by 2+ features live in
`lib/core/widgets/`; components specific to one feature's domain (e.g.
`ExerciseCard`) live in that feature's `presentation/widgets/` but are
still documented here so their contract is visible app-wide.

---

## Existing components (built in Phase 0 / Auth)

### `PrimaryButton`
`lib/core/widgets/primary_button.dart`

| Prop | Type | Notes |
|---|---|---|
| `label` | `String` | |
| `onPressed` | `VoidCallback?` | `null` renders disabled |
| `isLoading` | `bool` | Swaps label for a spinner, blocks re-tap |
| `variant` | `filled \| outlined` | Filled = primary action, outlined = secondary |

States: default, pressed (`animInstant` opacity dip), loading, disabled
(`primaryMuted` background). Height fixed at `AppSizing.buttonHeight`
(56px) — never shrunk for a "secondary" feel; use `variant: outlined`
for that instead.

### `AppTextField`
`lib/core/widgets/app_text_field.dart`

Label above, obscure-text toggle built in, validation error shown below
via the standard `TextFormField` mechanism. Used for form entry (Auth
today); **not** used for search — see `AppSearchField` below, which is a
visually and behaviorally distinct control.

### `LoadingOverlay`
`lib/core/widgets/loading_overlay.dart`

Full-bounds blocking scrim + spinner for async operations that must
prevent interaction (form submission). **Not** for list content loading
— see `SkeletonLoader`.

---

## New components (this sprint — Exercise Library)

### `AppSearchField`
`lib/core/widgets/app_search_field.dart`

| Prop | Type | Notes |
|---|---|---|
| `hintText` | `String` | |
| `onChanged` | `ValueChanged<String>` | Fires on every keystroke — search-as-you-type, no submit button |
| `onClear` | `VoidCallback?` | Called when the trailing X is tapped |

`pill`-radius, `surface` background, leading search icon (`iconSm`,
`textTertiary`), trailing clear icon that fades in (`animInstant`) only
once text is non-empty. Sits directly under the app bar, always visible
— never a separate search screen/route. Reused wherever list search
appears (History, future Workout Plans search).

### `AppFilterChip`
`lib/core/widgets/app_filter_chip.dart`

| Prop | Type | Notes |
|---|---|---|
| `label` | `String` | |
| `isSelected` | `bool` | |
| `onTap` | `VoidCallback` | |

36px height, `pill` radius. Rest: `surface` bg / `textSecondary` text.
Selected: `primaryMuted` at 20% opacity bg / `primary` text + 1px
`primary` border. Transitions on `animInstant`. Used standalone (quick
single-facet filters) and inside `FilterBottomSheet` (as a checkable
list item, same visual language, larger tap target in that context).

### `ExerciseCard`
`lib/features/exercises/presentation/widgets/exercise_card.dart`

| Prop | Type | Notes |
|---|---|---|
| `exercise` | `ExerciseSummary` | |
| `mode` | `browse \| picker` | Determines trailing control |
| `isSelected` | `bool` | Only meaningful in `picker` mode |
| `onTap` | `VoidCallback` | Navigates to detail (browse) or toggles selection (picker) |
| `onInfoTap` | `VoidCallback?` | Picker mode only — opens the detail bottom sheet without toggling selection |

`surface` background, `AppRadius.lg`, 64×64 lazy-loaded GIF thumbnail
(`SkeletonLoader`-shaped placeholder until loaded, see
`ExerciseThumbnail` below), title + single-line muscle/equipment
caption. Browse mode trailing: chevron. Picker mode trailing: checkbox
(filled + `primary`-tinted card border when selected) plus a small ⓘ
info affordance next to it.

### `ExerciseThumbnail`
`lib/features/exercises/presentation/widgets/exercise_thumbnail.dart`

Internal helper used by both `ExerciseCard` and `ExerciseDetailView` —
wraps `cached_network_image` with: `SkeletonLoader` while loading, a
muscle-group icon fallback (`iconLg`, `textTertiary`) on error, and a
cross-fade-in over `animFast` once loaded. This is where "lazy GIF
loading" is actually implemented — extracted as its own component so
every place a GIF appears (card, full-screen detail, bottom-sheet
detail) gets identical loading behavior for free rather than three
separate implementations.

### `FilterBottomSheet`
`lib/features/exercises/presentation/widgets/filter_bottom_sheet.dart`

Facets (muscle group, equipment, type) rendered as checkable
`AppFilterChip`-styled rows, grouped under section labels (`caption` style,
uppercase). "Apply (N)" primary button shows a live count of matching
results as facets toggle. "Clear all" resets every facet. `surfaceElevated`
background, `AppRadius.xl` top corners, max height ~70% of screen,
internal scroll if facet content exceeds that. Presented via
`showModalBottomSheet`, `animMedium` / `easeOutCubic` per the standard
timing table.

### `ExerciseDetailView`
`lib/features/exercises/presentation/widgets/exercise_detail_view.dart`

The shared content widget for exercise detail — **not** a screen itself.
Renders: `ExerciseThumbnail` (GIF, autoplay/muted/looping), name
(`headline`), muscle + equipment tags (`AppFilterChip` styling, inert —
`onTap: null`), instructions list. Takes an `ExerciseDetail` entity and
nothing else — no knowledge of whether it's inside a full route or a
sheet, which is exactly what makes it reusable across both contexts (see
`ExerciseDetailScreen` and `ExerciseDetailSheet` below).

### `ExerciseDetailScreen`
`lib/features/exercises/presentation/screens/exercise_detail_screen.dart`

Thin route wrapper: app bar with back button, `SafeArea`, scrollable
body containing `ExerciseDetailView`. Used for Context A (browse mode)
per `USER_FLOW.md` Flow 3.

### `ExerciseDetailSheet`
`lib/features/exercises/presentation/widgets/exercise_detail_sheet.dart`

Thin bottom-sheet wrapper: drag handle, `ExerciseDetailView` inside a
`DraggableScrollableSheet` capped at ~75% height, dismiss via swipe/tap-
outside/X. Used for Context B (picker mode, mid-workout) per
`USER_FLOW.md` Flow 3. Both wrappers exist specifically so
`ExerciseDetailView` itself never branches on presentation context —
the container decides how it's shown, the content never needs to know.

### `EmptyState`
`lib/core/widgets/empty_state.dart`

| Prop | Type | Notes |
|---|---|---|
| `icon` | `IconData` | |
| `title` | `String` | |
| `message` | `String` | |
| `actionLabel` | `String?` | Optional button (e.g. "Retry", "Clear filters") |
| `onAction` | `VoidCallback?` | |

Centered column, `iconLg` icon in `textTertiary`. One component for
every "list is legitimately empty" case app-wide — zero search results,
no network, and (later) empty history/plans — parameterized rather than
duplicated per feature.

### `SkeletonLoader`
`lib/core/widgets/skeleton_loader.dart`

| Prop | Type | Notes |
|---|---|---|
| `width` | `double?` | `null` fills available width |
| `height` | `double` | |
| `borderRadius` | `double` | Defaults to `AppRadius.sm` |

Shimmer sweep between `shimmerBase`/`shimmerHighlight`, `animShimmer`
duration, looping. Composed into shapes matching real content (e.g.
`ExerciseCardSkeleton`, a fixed arrangement of `SkeletonLoader` blocks
matching `ExerciseCard`'s layout) rather than used as a single generic
box — the skeleton should telegraph the real layout, not just "loading."

---

## Picker Mode — reusability contract

"Reusable Picker Mode" (per this sprint's approved refinements) means
the *same* `ExerciseLibraryScreen` widget serves both Flow 1 and Flow 4
from `USER_FLOW.md`, via one parameter:

```dart
ExerciseLibraryScreen(mode: ExerciseLibraryMode.browse)   // Flow 1, tab destination
ExerciseLibraryScreen(mode: ExerciseLibraryMode.picker)   // Flow 4, called by Workout Session (future)
```

Everything downstream branches on `mode`, not on which caller invoked
the screen — `ExerciseCard`'s trailing control, whether tapping a card
navigates or selects, whether a sticky "Add N Exercises" bar renders,
and whether the app bar shows a back chevron (browse) or an X (picker).
The data-fetching layer (search, filter, pagination) is identical in
both modes — only presentation branches. This is what lets Workout
Session adopt this screen later with zero changes to
`ExerciseLibraryScreen` itself, just a new call site passing
`mode: picker`.
