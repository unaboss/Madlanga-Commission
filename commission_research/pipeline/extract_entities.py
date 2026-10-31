"""
extract_entities.py — Extract named entities (people, orgs, dates, locations,
case numbers, exhibit refs) from normalized transcripts and statements.

Uses a hybrid of regex patterns + gazetteer lists from the inquiry's jurisdiction pack.
"""

import json
import re
from pathlib import Path
from collections import defaultdict

from inquiry_config import load_inquiry


DATA_DIR   = Path(__file__).resolve().parent.parent / "data"
INPUT_TRANSCRIPTS = DATA_DIR / "parsed" / "transcripts_normalized.jsonl"
INPUT_STATEMENTS  = DATA_DIR / "parsed" / "statements.jsonl"
OUTPUT_FILE = DATA_DIR / "parsed" / "entities.jsonl"


# ── Entity extraction patterns ──────────────────────────────────────
# Gazetteers and reference formats come from the jurisdiction pack
# (packs/<id>.json); inquiry-specific exhibit numbering (e.g. Madlanga's
# "MK" bundles) comes from the inquiry config.

_INQUIRY = load_inquiry()
_PACK = _INQUIRY["pack"]

ORGANISATIONS = _PACK.get("organisations", [])
LOCATIONS = _PACK.get("locations", [])

# Case/docket reference patterns
CASE_PATTERNS = [re.compile(p) for p in _PACK.get("case_patterns", [])]

# Exhibit/bundle references
EXHIBIT_PATTERNS = [re.compile(p) for p in
                    _PACK.get("exhibit_patterns", []) + _INQUIRY.get("exhibit_patterns", [])]

# Date patterns
DATE_PATTERNS = [
    re.compile(r"(\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4})"),
    re.compile(r"(\d{4}[/\-]\d{2}[/\-]\d{2})"),
    re.compile(r"(\d{1,2}[/\-]\d{1,2}[/\-]\d{4})"),
    re.compile(r"(\d{1,2}(?:st|nd|rd|th)\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4})"),
]

# Money amounts
MONEY_PATTERN = re.compile(_PACK["money_pattern"]) if _PACK.get("money_pattern") else None

# Vehicle registration
VEHICLE_PATTERN = re.compile(_PACK["vehicle_pattern"]) if _PACK.get("vehicle_pattern") else None


def extract_entities(text: str) -> list[dict]:
    """Extract all entities from a text segment."""
    entities = []

    # Organizations
    for org in ORGANISATIONS:
        if re.search(re.escape(org), text, re.IGNORECASE):
            entities.append({"type": "organization", "value": org})

    # Cases/dockets
    for pat in CASE_PATTERNS:
        for m in pat.finditer(text):
            entities.append({"type": "case_reference", "value": m.group(0).strip()})

    # Exhibits
    for pat in EXHIBIT_PATTERNS:
        for m in pat.finditer(text):
            entities.append({"type": "exhibit", "value": m.group(1).strip()})

    # Dates
    for pat in DATE_PATTERNS:
        for m in pat.finditer(text):
            entities.append({"type": "date", "value": m.group(1).strip()})

    # Locations
    for loc in LOCATIONS:
        if re.search(r"\b" + re.escape(loc) + r"\b", text, re.IGNORECASE):
            entities.append({"type": "location", "value": loc})

    # Money
    if MONEY_PATTERN:
        for m in MONEY_PATTERN.finditer(text):
            entities.append({"type": "money", "value": m.group(0).strip()})

    # Vehicles
    if VEHICLE_PATTERN:
        for m in VEHICLE_PATTERN.finditer(text):
            entities.append({"type": "vehicle", "value": m.group(0).strip()})

    return entities


def process_transcripts():
    """Extract entities from normalized transcripts."""
    if not INPUT_TRANSCRIPTS.exists():
        print(f"Transcripts not found: {INPUT_TRANSCRIPTS}")
        return 0

    print("Extracting entities from transcripts...")
    count = 0
    with open(INPUT_TRANSCRIPTS, encoding="utf-8") as fin, \
         open(OUTPUT_FILE, "a" if OUTPUT_FILE.exists() else "w", encoding="utf-8") as fout:
        for i, line in enumerate(fin):
            line = line.strip()
            if not line:
                continue
            seg = json.loads(line)
            entities = extract_entities(seg["text"])
            for ent in entities:
                rec = {
                    "source": "transcript",
                    "day": seg["day"],
                    "date": seg["date"],
                    "speaker": seg["speaker_canonical"],
                    "speaker_role": seg["speaker_role"],
                    "entity_type": ent["type"],
                    "entity_value": ent["value"],
                    "context": seg["text"][:300],
                    "page": seg.get("page", 0),
                    "line_start": seg.get("line_start", 0),
                    "page_end": seg.get("page_end", seg.get("page", 0)),
                    "line_end": seg.get("line_end", 0),
                }
                fout.write(json.dumps(rec, ensure_ascii=False) + "\n")
                count += 1
            if (i + 1) % 20000 == 0:
                print(f"  {i+1} segments processed  ({count} entities)")

    print(f"  Transcript entities: {count}")
    return count


def process_statements():
    """Extract entities from witness/media statements."""
    if not INPUT_STATEMENTS.exists():
        print(f"Statements not found: {INPUT_STATEMENTS}")
        return 0

    print("Extracting entities from statements...")
    count = 0
    with open(INPUT_STATEMENTS, encoding="utf-8") as fin, \
         open(OUTPUT_FILE, "a", encoding="utf-8") as fout:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            stmt = json.loads(line)
            entities = extract_entities(stmt["full_text"])
            for ent in entities:
                rec = {
                    "source": "statement",
                    "day": stmt.get("hearing_day", 0),
                    "date": stmt.get("hearing_date", ""),
                    "speaker": stmt.get("author", ""),
                    "speaker_role": stmt.get("type", "statement"),
                    "entity_type": ent["type"],
                    "entity_value": ent["value"],
                    "context": stmt["full_text"][:300],
                }
                fout.write(json.dumps(rec, ensure_ascii=False) + "\n")
                count += 1
    print(f"  Statement entities: {count}")
    return count


def main():
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    # Clear existing output
    if OUTPUT_FILE.exists():
        OUTPUT_FILE.unlink()

    t_count = process_transcripts()
    s_count = process_statements()
    total = t_count + s_count
    print(f"\nTotal entities extracted: {total}")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
