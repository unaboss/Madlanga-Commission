#!/usr/bin/env python3
"""Shared loader for the license HMAC secret.

The secret is read from the MADLANGA_LICENSE_SECRET environment variable,
falling back to the gitignored .license_secret file at the project root.
Import from here rather than duplicating the logic in each tool.
"""

import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def load_secret() -> bytes:
    """Return the license HMAC secret as bytes from env or the gitignored file."""
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
