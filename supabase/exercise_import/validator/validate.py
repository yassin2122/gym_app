"""
Validator stage of the exercise import pipeline.

Checks the transformer's output against the constraints the database
will actually enforce (so violations are caught here, with a clear
message, rather than as an opaque SQL error during import), plus checks
that wouldn't be caught by the database at all (duplicate slugs within
the batch, dead image URLs).

Run: python3 validate.py
Reads:  ../transformer/normalized_exercises.json
Writes: ./validated_exercises.json  (only if validation passes)
"""
import json
import random
import urllib.request
from pathlib import Path
from collections import Counter

IN_PATH = Path(__file__).parent.parent / "transformer" / "normalized_exercises.json"
OUT_PATH = Path(__file__).parent / "validated_exercises.json"

VALID_MECHANICS = {"compound", "isolation", None}
VALID_FORCE = {"push", "pull", "static", None}
VALID_DIFFICULTY = {"beginner", "intermediate", "advanced", None}
VALID_EXERCISE_TYPE = {"strength", "cardio", "mobility", "calisthenics"}

# How many image URLs to actually fetch and check resolve — a full check
# of 350+ URLs is unnecessary network load for what's meant to catch
# systematic problems (a wrong base URL), not verify every single asset.
URL_SAMPLE_SIZE = 15


def check_url_sample(records):
    all_urls = [img for r in records for img in r["images"]]
    sample = random.sample(all_urls, min(URL_SAMPLE_SIZE, len(all_urls)))
    failures = []
    for url in sample:
        try:
            req = urllib.request.Request(url, method="HEAD")
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status >= 400:
                    failures.append((url, resp.status))
        except Exception as e:  # noqa: BLE001
            failures.append((url, str(e)))
    return sample, failures


def main():
    records = json.loads(IN_PATH.read_text())
    errors = []

    slugs = Counter(r["slug"] for r in records)
    dupes = [s for s, c in slugs.items() if c > 1]
    if dupes:
        errors.append(f"Duplicate slugs: {dupes}")

    for r in records:
        if not r["name"] or not r["name"].strip():
            errors.append(f"{r['source_id']}: empty name")
        if r["mechanics"] not in VALID_MECHANICS:
            errors.append(f"{r['slug']}: invalid mechanics {r['mechanics']!r}")
        if r["force"] not in VALID_FORCE:
            errors.append(f"{r['slug']}: invalid force {r['force']!r}")
        if r["difficulty"] not in VALID_DIFFICULTY:
            errors.append(f"{r['slug']}: invalid difficulty {r['difficulty']!r}")
        if r["exercise_type"] not in VALID_EXERCISE_TYPE:
            errors.append(f"{r['slug']}: invalid exercise_type {r['exercise_type']!r}")
        if not r["primary_muscles"]:
            errors.append(f"{r['slug']}: no primary muscle")
        if not r["instructions"]:
            errors.append(f"{r['slug']}: no instructions")

    print(f"Checking {len(records)} records...")
    if errors:
        print(f"FAILED — {len(errors)} validation errors:")
        for e in errors[:20]:
            print(" -", e)
        raise SystemExit(1)
    print("Schema/constraint validation: PASS")

    print(f"Sampling {URL_SAMPLE_SIZE} image URLs for a live reachability check...")
    sample, failures = check_url_sample(records)
    print(f"Checked {len(sample)} URLs, {len(failures)} failed:")
    for url, reason in failures:
        print(" -", url, reason)
    if failures and len(failures) == len(sample):
        raise SystemExit("All sampled URLs failed — likely a systematic base-URL problem, aborting.")

    OUT_PATH.write_text(json.dumps(records, indent=2))
    print(f"Validation PASSED. Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
