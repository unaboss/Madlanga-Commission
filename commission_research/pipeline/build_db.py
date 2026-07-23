"""
build_db.py — Run the full data processing pipeline.

Usage:
    python pipeline/build_db.py          # Run all steps
    python pipeline/build_db.py --step parse  # Run a specific step

Steps:
    1. parse    — Parse transcripts and extract text from statement PDFs
    2. norm     — Normalize speaker names
    3. extract  — Extract entities
    4. index    — Build SQLite FTS5 search database
    5. network  — Compute network graph for dashboard
    6. storymap — Build story map timeline for dashboard
"""

import sys
import subprocess
from pathlib import Path


PIPELINE_DIR = Path(__file__).resolve().parent
STEPS = {
    "parse":   [PIPELINE_DIR / "parse_transcripts.py",
                PIPELINE_DIR / "parse_statements.py"],
    "norm":    [PIPELINE_DIR / "normalize_speakers.py"],
    "extract": [PIPELINE_DIR / "extract_entities.py"],
    "index":   [PIPELINE_DIR / "index_search.py"],
    "network": [PIPELINE_DIR / "compute_network.py"],
    "storymap": [PIPELINE_DIR / "build_story_map.py"],
}


def run_step(name: str, scripts: list[Path]):
    print(f"\n{'='*60}")
    print(f"  STEP: {name}")
    print(f"{'='*60}")
    for script in scripts:
        if not script.exists():
            print(f"  SKIP: {script.name} not found")
            continue
        print(f"\n  Running {script.name}...")
        result = subprocess.run([sys.executable, str(script)], capture_output=False)
        if result.returncode != 0:
            print(f"  ERROR: {script.name} failed with code {result.returncode}")
            sys.exit(1)


def main():
    step_arg = None
    if len(sys.argv) > 1:
        if sys.argv[1] == "--step" and len(sys.argv) > 2:
            step_arg = sys.argv[2]
        else:
            step_arg = sys.argv[1].lstrip("-")

    if step_arg:
        if step_arg not in STEPS:
            print(f"Unknown step: {step_arg}")
            print(f"Available: {', '.join(STEPS.keys())}")
            sys.exit(1)
        run_step(step_arg, STEPS[step_arg])
    else:
        for name, scripts in STEPS.items():
            run_step(name, scripts)

    print(f"\n{'='*60}")
    print("  Pipeline complete.")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
