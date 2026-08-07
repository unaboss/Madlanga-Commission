#!/usr/bin/env python3
"""Generate a signed license.key for the Commission Research Dashboard.

Usage:
  python generate_license.py "Madlanga Commission" --tier starter --months 1 --output license.key

Tiers:
  starter      - Base dashboard (R20,000/month)
  professional - +Evidence Bundle, Witness Prep, Smart Search (R35,000/month)
  enterprise   - +Contradiction Engine, Report Drafting, Multi-user (R55,000/month)
"""

import json
import hmac
import hashlib
import os
from datetime import datetime, timedelta
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def load_secret() -> bytes:
    env_secret = os.environ.get("MADLANGA_LICENSE_SECRET")
    if env_secret:
        return env_secret.encode()

    secret_file = PROJECT_ROOT / ".license_secret"
    if secret_file.exists():
        return secret_file.read_text().strip().encode()

    raise RuntimeError(
        "License secret not configured. Set MADLANGA_LICENSE_SECRET or "
        "create .license_secret at the project root."
    )


SECRET_KEY = load_secret()
VALID_TIERS = ("starter", "professional", "enterprise")


def generate_license(customer: str, tier: str = "starter", months: int = 1, output: str = "license.key"):
    if tier not in VALID_TIERS:
        print(f"ERROR: Invalid tier '{tier}'. Choose from: {', '.join(VALID_TIERS)}")
        return None

    issued = datetime.now().strftime("%Y-%m-%d")
    expiry = (datetime.now() + timedelta(days=30 * months)).strftime("%Y-%m-%d")

    payload = f"{customer}|{tier}|{expiry}|{issued}"
    sig = hmac.new(SECRET_KEY, payload.encode(), hashlib.sha256).hexdigest()

    license_data = {
        "customer": customer,
        "tier": tier,
        "expiry": expiry,
        "issued": issued,
        "sig": sig,
    }

    path = Path(output)
    path.write_text(json.dumps(license_data, indent=2))
    print(f"License generated for '{customer}'")
    print(f"  Tier:    {tier.upper()}")
    print(f"  Issued:  {issued}")
    print(f"  Expires: {expiry}")
    print(f"  Saved:   {path.resolve()}")
    return path


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate a license.key file")
    parser.add_argument("customer", help="Customer name (e.g. 'Madlanga Commission')")
    parser.add_argument(
        "--tier", choices=VALID_TIERS, default="starter",
        help="License tier (default: starter)"
    )
    parser.add_argument("--months", type=int, default=1, help="Number of months valid")
    parser.add_argument("--output", default="license.key", help="Output path")
    args = parser.parse_args()
    generate_license(args.customer, args.tier, args.months, args.output)
