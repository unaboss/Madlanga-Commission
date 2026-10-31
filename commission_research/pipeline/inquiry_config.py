"""
inquiry_config.py — Load the settings for the inquiry being processed.

Everything specific to one inquiry (speaker names, the focus witness, exhibit
numbering, where its downloads live) sits in inquiries/<id>/inquiry.json.
Everything specific to a country (organisations, places, case-number and
money formats) sits in packs/<pack>.json. The pipeline and the dashboard read
these instead of hard-coding Madlanga.

Pick an inquiry with the INQUIRY_CONFIG environment variable (a path to its
inquiry.json); the default is the Madlanga Commission.
"""

import json
import os
import re
from functools import lru_cache
from pathlib import Path


COMMISSION_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = COMMISSION_DIR.parent
DEFAULT_CONFIG = COMMISSION_DIR / "inquiries" / "madlanga" / "inquiry.json"
PACKS_DIR = COMMISSION_DIR / "packs"
APP_CONFIG = COMMISSION_DIR / "app" / "inquiry.json"

VALID_ROLES = {"commissioner", "evidence_leader", "witness", "witness_protected", "other"}


class InquiryConfigError(ValueError):
    pass


def config_path() -> Path:
    env = os.environ.get("INQUIRY_CONFIG", "").strip()
    return Path(env).expanduser().resolve() if env else DEFAULT_CONFIG


def _read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise InquiryConfigError(f"Config file not found: {path}")
    except json.JSONDecodeError as e:
        raise InquiryConfigError(f"{path} is not valid JSON: {e}")


def _compile(pattern: str, where: str, flags=0) -> re.Pattern:
    try:
        return re.compile(pattern, flags)
    except re.error as e:
        raise InquiryConfigError(f"Bad regex in {where}: {pattern!r} ({e})")


def validate(inquiry: dict, pack: dict, path: Path = None) -> None:
    """Raise InquiryConfigError naming the first problem, so a customer's
    config fails at load time rather than halfway through a pipeline run."""
    where = str(path or "inquiry config")
    for key in ("id", "short_name", "jurisdiction_pack", "source_dir"):
        if not str(inquiry.get(key, "")).strip():
            raise InquiryConfigError(f"{where}: '{key}' is required")
    for i, rule in enumerate(inquiry.get("speaker_rules", [])):
        if not (isinstance(rule, list) and len(rule) == 3):
            raise InquiryConfigError(f"{where}: speaker_rules[{i}] must be [regex, name, role]")
        _compile(rule[0], f"speaker_rules[{i}]", re.IGNORECASE)
        if rule[2] not in VALID_ROLES:
            raise InquiryConfigError(
                f"{where}: speaker_rules[{i}] role '{rule[2]}' must be one of {sorted(VALID_ROLES)}")
    for i, p in enumerate(inquiry.get("exhibit_patterns", [])):
        _compile(p, f"exhibit_patterns[{i}]")
    for key in ("case_patterns", "exhibit_patterns"):
        for i, p in enumerate(pack.get(key, [])):
            _compile(p, f"pack {key}[{i}]")
    for key in ("money_pattern", "vehicle_pattern"):
        if pack.get(key):
            _compile(pack[key], f"pack {key}")


@lru_cache(maxsize=None)
def _load(path_str: str) -> dict:
    path = Path(path_str)
    inquiry = _read_json(path)
    pack_id = str(inquiry.get("jurisdiction_pack", "")).strip()
    pack = _read_json(PACKS_DIR / f"{pack_id}.json") if pack_id else {}
    validate(inquiry, pack, path)
    inquiry["pack"] = pack
    inquiry["config_file"] = str(path)
    return inquiry


def load_inquiry() -> dict:
    """The active inquiry's settings, with its jurisdiction pack under 'pack'."""
    return _load(str(config_path()))


def source_dir() -> Path:
    """Where the inquiry's downloaded records live (relative paths are from the repo root)."""
    p = Path(load_inquiry()["source_dir"]).expanduser()
    return p if p.is_absolute() else REPO_ROOT / p


def speaker_rules() -> list[tuple[re.Pattern, str, str]]:
    return _speaker_rules(str(config_path()))


@lru_cache(maxsize=None)
def _speaker_rules(path_str: str) -> list[tuple[re.Pattern, str, str]]:
    return [(re.compile(p, re.IGNORECASE), name, role)
            for p, name, role in _load(path_str).get("speaker_rules", [])]


def focus_match() -> str:
    """Text that identifies the inquiry's central witness in node labels ('' if none)."""
    return (load_inquiry().get("focus_person") or {}).get("match", "") or ""


def is_focus(label: str) -> bool:
    m = focus_match()
    return bool(m) and m.lower() in (label or "").lower()


def write_app_config(target: Path = APP_CONFIG) -> Path:
    """Write the settings the dashboard needs next to app.R, so a deployed app
    (which only ships the app/ folder) shows the right inquiry."""
    inq = load_inquiry()
    keys = ("id", "short_name", "name", "branding", "contact", "focus_person", "disclaimer")
    app_cfg = {k: inq[k] for k in keys if k in inq}
    target.write_text(json.dumps(app_cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return target


if __name__ == "__main__":
    inq = load_inquiry()
    print(f"Inquiry: {inq['short_name']} ({inq['config_file']})")
    print(f"  Pack:        {inq['pack'].get('name', inq['jurisdiction_pack'])}")
    print(f"  Source dir:  {source_dir()}")
    print(f"  Speaker rules: {len(inq.get('speaker_rules', []))}")
    print(f"  Wrote {write_app_config()}")
