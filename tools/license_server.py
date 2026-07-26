#!/usr/bin/env python3
"""Optional remote license validation server.

Run on your server:
  python license_server.py

The app phones home to this endpoint for additional validation.
"""

import json
import hmac
import hashlib
from datetime import datetime
from pathlib import Path

from flask import Flask, request, jsonify

app = Flask(__name__)

# MUST match SECRET_KEY in license_check.r
SECRET_KEY = b"[rotated-secret-removed]"

# Persisted revoked keys
REVOKED_FILE = Path("revoked_keys.json")
revoked_keys = set()
if REVOKED_FILE.exists():
    revoked_keys = set(json.loads(REVOKED_FILE.read_text()))


def save_revoked():
    REVOKED_FILE.write_text(json.dumps(list(revoked_keys)))


@app.route("/api/check-license", methods=["GET"])
def check_license():
    key = request.args.get("key", "")
    customer = request.args.get("customer", "")

    if key in revoked_keys:
        return jsonify({"status": "revoked", "message": "License revoked"}), 403

    return jsonify({"status": "ok", "message": "License valid"}), 200


@app.route("/api/revoke", methods=["POST"])
def revoke():
    data = request.get_json(force=True)
    key = data.get("key", "")
    if key:
        revoked_keys.add(key)
        save_revoked()
        return jsonify({"status": "revoked", "message": f"Key revoked ({len(revoked_keys)} total)"}), 200
    return jsonify({"status": "error", "message": "No key provided"}), 400


@app.route("/api/list-revoked", methods=["GET"])
def list_revoked():
    return jsonify({"revoked_count": len(revoked_keys), "keys": list(revoked_keys)}), 200


if __name__ == "__main__":
    print("License validation server starting on port 8443...")
    print(f"  Revoked keys: {len(revoked_keys)}")
    app.run(host="0.0.0.0", port=8443, ssl_context="adhoc")
