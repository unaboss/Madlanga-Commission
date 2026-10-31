"""
normalize_speakers.py — Map transcript speaker-label variants to canonical names.

Reads transcripts.jsonl, applies normalization rules, writes back with
a `speaker_canonical` field.
"""

import json
import re
from pathlib import Path

from inquiry_config import speaker_rules


DATA_DIR   = Path(__file__).resolve().parent.parent / "data"
INPUT_FILE  = DATA_DIR / "parsed" / "transcripts.jsonl"
OUTPUT_FILE = DATA_DIR / "parsed" / "transcripts_normalized.jsonl"


# ── Normalization rules ─────────────────────────────────────────────
# Rules live in the inquiry config ("speaker_rules"): [regex, canonical_name, role]
#   role: "commissioner" | "evidence_leader" | "witness" | "witness_protected" | "other"
#   Patterns are checked in order; first match wins. "{1}" in a name is
#   replaced by the regex's first group (e.g. "Witness {1} (protected)").


def _expand(canonical: str, match: re.Match) -> str:
    return re.sub(r"\{(\d+)\}", lambda g: match.group(int(g.group(1))) or "", canonical)


def normalize_speaker(raw_speaker: str) -> tuple[str, str]:
    """Return (canonical_name, role) for a raw speaker label."""
    raw = raw_speaker.strip().upper()

    for pattern, canonical, role in speaker_rules():
        match = pattern.match(raw)
        if match:
            return (_expand(canonical, match), role)

    # Unknown speaker — clean up but keep as-is
    clean = re.sub(r"\s+", " ", raw_speaker.strip()).title()
    return (clean, "other")


def normalize_all():
    """Read transcripts.jsonl, normalize speakers, write output."""
    print("Normalizing speakers...")
    if not INPUT_FILE.exists():
        print(f"Input file not found: {INPUT_FILE}")
        print("Run parse_transcripts.py first.")
        return

    seen = set()
    roles_ct = {}
    with open(INPUT_FILE, encoding="utf-8") as fin, \
         open(OUTPUT_FILE, "w", encoding="utf-8") as fout:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            seg = json.loads(line)
            raw = seg["speaker"]
            canonical, role = normalize_speaker(raw)

            seg["speaker_canonical"] = canonical
            seg["speaker_role"] = role

            fout.write(json.dumps(seg, ensure_ascii=False) + "\n")

            if raw not in seen:
                seen.add(raw)
                roles_ct[role] = roles_ct.get(role, 0) + 1

    print(f"  {len(seen)} unique raw speaker labels mapped")
    print(f"  Roles: {dict(roles_ct)}")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    normalize_all()
