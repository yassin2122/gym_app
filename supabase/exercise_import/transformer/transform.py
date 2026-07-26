"""
Transformer stage of the exercise import pipeline.

Reads the raw free-exercise-db dataset (public domain,
github.com/yuhonas/free-exercise-db) and maps it onto this project's
schema: category -> exercise_categories/exercise_type, muscles -> the
muscle_groups taxonomy, equipment -> the equipment taxonomy, generates a
URL-safe slug, and selects a curated subset with complete metadata.

Run: python3 transform.py
Reads:  ../raw/free_exercise_db.json
Writes: ../transformer/normalized_exercises.json  (staging output, read
        by the validator next)
"""
import json
import re
from pathlib import Path
from collections import Counter

RAW_PATH = Path(__file__).parent.parent / "raw" / "free_exercise_db.json"
OUT_PATH = Path(__file__).parent / "normalized_exercises.json"

# Per-category caps so the curated 350 actually spans categories instead
# of being filled entirely by the largest one (strength has 581 raw rows
# on its own — a flat sort-then-truncate would silently produce a
# 100%-strength library). Cardio has very few complete rows in the
# source data at all, so it's uncapped (take everything available).
CATEGORY_CAPS = {
    "strength": 220,
    "cardio": 999,
    "stretching": 60,
    "plyometrics": 30,
    "powerlifting": 20,
    "olympic weightlifting": 15,
    "strongman": 10,
}

# Category priority: the everyday gym movements first, specialist
# categories (powerlifting/oly/strongman) filled in after, so the curated
# set is weighted toward what a typical user's Exercise Library needs.
CATEGORY_PRIORITY = [
    "strength", "cardio", "stretching",
    "plyometrics", "powerlifting", "olympic weightlifting", "strongman",
]

# Muscle name -> body_region. Every value here is a real muscle name
# that actually appears in the dataset (verified below), not invented.
MUSCLE_BODY_REGION = {
    "quadriceps": "lower_body", "hamstrings": "lower_body", "calves": "lower_body",
    "glutes": "lower_body", "adductors": "lower_body", "abductors": "lower_body",
    "shoulders": "upper_body", "chest": "upper_body", "triceps": "upper_body",
    "biceps": "upper_body", "lats": "upper_body", "middle back": "upper_body",
    "forearms": "upper_body", "traps": "upper_body", "neck": "upper_body",
    "abdominals": "core", "lower back": "core",
}

# Raw equipment value -> (display name, equipment_category). Covers every
# value actually present in the dataset, including null.
EQUIPMENT_MAP = {
    "barbell": ("Barbell", "free_weight"),
    "dumbbell": ("Dumbbell", "free_weight"),
    "kettlebells": ("Kettlebell", "free_weight"),
    "e-z curl bar": ("EZ Curl Bar", "free_weight"),
    "cable": ("Cable", "cable"),
    "machine": ("Machine", "machine"),
    "body only": ("Bodyweight", "bodyweight"),
    "bands": ("Resistance Band", "accessory"),
    "medicine ball": ("Medicine Ball", "accessory"),
    "exercise ball": ("Exercise Ball", "accessory"),
    "foam roll": ("Foam Roller", "accessory"),
    "other": ("Other", "accessory"),
    None: ("Other", "accessory"),
}

CATEGORY_TO_EXERCISE_TYPE = {
    "strength": "strength", "powerlifting": "strength",
    "olympic weightlifting": "strength", "strongman": "strength",
    "plyometrics": "strength", "cardio": "cardio", "stretching": "mobility",
}

LEVEL_MAP = {"beginner": "beginner", "intermediate": "intermediate", "expert": "advanced"}

IMAGE_BASE_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"


def slugify(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def is_complete(row: dict) -> bool:
    return bool(
        row.get("force") and row.get("level") and row.get("mechanic")
        and row.get("primaryMuscles") and row.get("instructions")
    )


def transform_row(row: dict) -> dict:
    category = row["category"]
    equipment_name, equipment_category = EQUIPMENT_MAP.get(row.get("equipment"), EQUIPMENT_MAP["other"])

    return {
        "source_id": row["id"],
        "name": row["name"],
        "slug": slugify(row["id"]),
        "description": None,
        "category": category,
        "exercise_type": CATEGORY_TO_EXERCISE_TYPE.get(category, "strength"),
        "movement_pattern": None,  # not derivable from source data — left null, not fabricated
        "mechanics": row.get("mechanic"),
        "force": row.get("force"),
        "difficulty": LEVEL_MAP.get(row.get("level")),
        "primary_muscles": row.get("primaryMuscles", []),
        "secondary_muscles": row.get("secondaryMuscles", []),
        "equipment_name": equipment_name,
        "equipment_category": equipment_category,
        "instructions": row.get("instructions", []),
        "images": [IMAGE_BASE_URL + img for img in row.get("images", [])],
    }


def main():
    raw = json.loads(RAW_PATH.read_text())
    complete = [r for r in raw if is_complete(r)]

    # Verify every muscle name we're about to rely on is one we've
    # actually mapped — fail loudly rather than silently drop data.
    seen_muscles = set()
    for r in complete:
        seen_muscles.update(r.get("primaryMuscles", []))
        seen_muscles.update(r.get("secondaryMuscles", []))
    unmapped = seen_muscles - set(MUSCLE_BODY_REGION)
    if unmapped:
        raise SystemExit(f"Unmapped muscle names found in source data: {unmapped}")

    # Curate: within each category, take up to its cap, sorted
    # alphabetically for deterministic output.
    by_category = {}
    for r in complete:
        by_category.setdefault(r["category"], []).append(r)

    selected = []
    for category in CATEGORY_PRIORITY:
        rows = sorted(by_category.get(category, []), key=lambda r: r["name"])
        cap = CATEGORY_CAPS.get(category, 0)
        selected.extend(rows[:cap])

    normalized = [transform_row(r) for r in selected]

    OUT_PATH.write_text(json.dumps(normalized, indent=2))

    print(f"Source rows: {len(raw)}")
    print(f"Complete-metadata rows: {len(complete)}")
    print(f"Selected (per-category capped): {len(selected)}")
    print("By category:", Counter(r["category"] for r in normalized))
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
