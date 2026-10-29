import hashlib
import hmac
import json
from datetime import datetime

import pytest

import update_and_renew
from generate_license import build_license, sign_license

NOW = datetime(2026, 8, 7)


def test_signature_matches_the_payload_the_r_app_verifies():
    lic = build_license("Acme Legal", "professional", 3, secret=b"s3cret", now=NOW)
    payload = f"Acme Legal|professional|{lic['expiry']}|2026-08-07"
    assert lic["sig"] == hmac.new(b"s3cret", payload.encode(), hashlib.sha256).hexdigest()
    assert lic["issued"] == "2026-08-07"
    assert lic["expiry"] == "2026-11-05"


def test_invalid_tier_is_rejected():
    with pytest.raises(ValueError):
        build_license("Acme Legal", "platinum", secret=b"s3cret")


def test_renewal_package_writes_a_license_with_a_tier(tmp_path, monkeypatch):
    # The renewal tool used to sign without the tier, so every renewed
    # license failed the dashboard's signature check.
    monkeypatch.setattr(update_and_renew, "APP_DATA_DIR", tmp_path / "data")
    monkeypatch.setattr(update_and_renew, "APP_WWW_DIR", tmp_path / "www")
    out = tmp_path / "pkg"
    update_and_renew.package_update(str(out), "Acme Legal", 1, "enterprise")
    lic = json.loads((out / "license.key").read_text())
    assert lic["tier"] == "enterprise"
    assert lic["sig"] == sign_license(b"test-secret", lic["customer"], lic["tier"],
                                      lic["expiry"], lic["issued"])
