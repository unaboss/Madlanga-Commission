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
from datetime import datetime, timedelta
from pathlib import Path

from license_secret import load_secret

VALID_TIERS = ("starter", "professional", "enterprise")


def sign_license(secret: bytes, customer: str, tier: str, expiry: str, issued: str) -> str:
    """HMAC-SHA256 over the payload app/license_check.r verifies."""
    payload = f"{customer}|{tier}|{expiry}|{issued}"
    return hmac.new(secret, payload.encode(), hashlib.sha256).hexdigest()


def build_license(customer: str, tier: str = "starter", months: int = 1,
                  secret: bytes | None = None, now: datetime | None = None) -> dict:
    """Return a signed license dict for `customer`."""
    if tier not in VALID_TIERS:
        raise ValueError(f"Invalid tier '{tier}'. Choose from: {', '.join(VALID_TIERS)}")
    secret = load_secret() if secret is None else secret
    now = now or datetime.now()
    issued = now.strftime("%Y-%m-%d")
    expiry = (now + timedelta(days=30 * months)).strftime("%Y-%m-%d")
    return {
        "customer": customer,
        "tier": tier,
        "expiry": expiry,
        "issued": issued,
        "sig": sign_license(secret, customer, tier, expiry, issued),
    }


def generate_license(customer: str, tier: str = "starter", months: int = 1, output: str = "license.key"):
    if tier not in VALID_TIERS:
        print(f"ERROR: Invalid tier '{tier}'. Choose from: {', '.join(VALID_TIERS)}")
        return None

    license_data = build_license(customer, tier, months)
    issued, expiry = license_data["issued"], license_data["expiry"]

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
