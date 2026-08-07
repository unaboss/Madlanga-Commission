#!/usr/bin/env python3
"""Run the full data pipeline, generate a new license, and package the update.

Usage:
  python update_and_renew.py                    # Full pipeline + license
  python update_and_renew.py --skip-pipeline    # Just regenerate license
"""

import json
import hmac
import hashlib
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

from license_secret import load_secret

SECRET_KEY = load_secret()

# Paths relative to project root
PROJECT_ROOT = Path(__file__).resolve().parent.parent
PIPELINE_DIR = PROJECT_ROOT / "commission_research" / "pipeline"
DOWNLOADER = PROJECT_ROOT / "madlanga_downloader.py"
APP_DATA_DIR = PROJECT_ROOT / "commission_research" / "app" / "data"
APP_WWW_DIR = PROJECT_ROOT / "commission_research" / "app" / "www"
PARSED_DIR = PROJECT_ROOT / "commission_research" / "data" / "parsed"
PIPELINE_SCRIPTS = [
    "extract_entities.py",
    "build_db.py",
    "compute_network.py",
    "build_story_map.py",
]


def run_pipeline():
    """Download new data and run all pipeline stages."""
    print("=" * 60)
    print("  STEP 1: Download new data from Supabase")
    print("=" * 60)
    result = subprocess.run(
        [sys.executable, str(DOWNLOADER), "--no-extract", "--overwrite"],
        capture_output=True, text=True, cwd=PROJECT_ROOT,
    )
    print(result.stdout)
    if result.returncode != 0:
        print("ERROR: Data download failed")
        print(result.stderr)
        sys.exit(1)

    print("\n" + "=" * 60)
    print("  STEP 2: Run NLP pipeline")
    print("=" * 60)
    for script in PIPELINE_SCRIPTS:
        script_path = PIPELINE_DIR / script
        if not script_path.exists():
            print(f"  SKIP: {script} not found")
            continue
        print(f"  Running {script}...")
        result = subprocess.run(
            [sys.executable, str(script_path)],
            capture_output=True, text=True, cwd=PIPELINE_DIR,
        )
        print(result.stdout[-500:] if len(result.stdout) > 500 else result.stdout)
        if result.returncode != 0:
            print(f"  WARNING: {script} exited with code {result.returncode}")
            print(result.stderr[-300:])

    print("\n" + "=" * 60)
    print("  STEP 3: Copy fresh data to app directory")
    print("=" * 60)
    APP_DATA_DIR.mkdir(parents=True, exist_ok=True)
    APP_WWW_DIR.mkdir(parents=True, exist_ok=True)

    db_src = PROJECT_ROOT / "commission_research" / "data" / "commission_research.db"
    if db_src.exists():
        shutil.copy(str(db_src), str(APP_DATA_DIR / "commission_research.db"))
        print(f"  Copied: commission_research.db")

    for fname in ["network_data.json", "story_map_data.json"]:
        src = PARSED_DIR / fname
        if src.exists():
            shutil.copy(str(src), str(APP_WWW_DIR / fname))
            print(f"  Copied: {fname}")

    print("  Pipeline complete.\n")


def generate_license(customer: str, months: int = 1):
    """Generate a signed license dict."""
    issued = datetime.now().strftime("%Y-%m-%d")
    expiry = (datetime.now() + timedelta(days=30 * months)).strftime("%Y-%m-%d")
    payload = f"{customer}|{expiry}|{issued}"
    sig = hmac.new(SECRET_KEY, payload.encode(), hashlib.sha256).hexdigest()
    return {
        "customer": customer,
        "expiry": expiry,
        "issued": issued,
        "sig": sig,
    }


def package_update(output_dir: str = "update_package", customer: str = "Madlanga Commission", months: int = 1):
    """Copy data files and generate a new license into a clean package."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Copy data files
    db_file = APP_DATA_DIR / "commission_research.db"
    if db_file.exists():
        shutil.copy(str(db_file), str(out / "commission_research.db"))
    for fname in ["network_data.json", "story_map_data.json"]:
        src = APP_WWW_DIR / fname
        if src.exists():
            shutil.copy(str(src), str(out / fname))

    # Generate and write license
    lic = generate_license(customer, months)
    (out / "license.key").write_text(json.dumps(lic, indent=2))

    print("=" * 60)
    print("  UPDATE PACKAGE READY")
    print("=" * 60)
    print(f"  Customer: {customer}")
    print(f"  License expires: {lic['expiry']}")
    print(f"  Package path: {out.resolve()}")
    print()
    print("  Files to deploy:")
    for f in out.iterdir():
        print(f"    {f.name}")
    print()
    print("  Deploy: copy these files over the existing app/ directory.")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Update data and renew license")
    parser.add_argument(
        "--skip-pipeline",
        action="store_true",
        help="Skip data download and pipeline, just generate new license",
    )
    parser.add_argument(
        "--customer",
        default="Madlanga Commission",
        help="Customer name for the license",
    )
    parser.add_argument(
        "--months",
        type=int,
        default=1,
        help="Number of months the license is valid for",
    )
    parser.add_argument(
        "--output",
        default="update_package",
        help="Output directory for the update package",
    )
    args = parser.parse_args()

    if not args.skip_pipeline:
        run_pipeline()

    package_update(args.output, args.customer, args.months)
