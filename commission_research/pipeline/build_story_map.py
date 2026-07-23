"""
build_story_map.py — Build story map timeline data for the Shiny dashboard.
Creates two parallel timelines:
  1. Commission Evidence Timeline — from documents (rulings, applications, statements)
  2. Witness Testimony Timeline — from hearing transcripts grouped by day/speaker

Output: app/www/story_map_data.json
"""

import sqlite3
import json
import re
from pathlib import Path
from collections import defaultdict

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "commission_research.db"
OUT_DIR = Path(__file__).resolve().parent.parent / "app" / "www"
OUTPUT_FILE = OUT_DIR / "story_map_data.json"

# Entity extraction patterns (lightweight keyword matching for document titles)
ORG_PATTERNS = [
    "SAPS", "HAWKS", "DPCI", "NPA", "IPID", "SIU", "SSA",
    "Crime Intelligence", "National Prosecuting Authority",
    "Independent Police Investigative Directorate",
    "State Security Agency", "Special Investigating Unit",
    "Task Team", "National Task Team",
    "Organised Crime", "Detective Services", "Visible Policing",
    "Crime Intelligence Division", "NATJOINTS",
    "Medicare", "Carnilinx", "Forensic Science Laboratory",
    "National Intervention Unit", "Tactical Response Team",
    "Scorpions", "Directorate Special Operations",
]

LOCATIONS = [
    "Gauteng", "KwaZulu-Natal", "KZN", "Western Cape", "Eastern Cape",
    "Limpopo", "Mpumalanga", "North West", "Northern Cape", "Free State",
    "Pretoria", "Johannesburg", "Cape Town", "Durban",
]

STOP_WORDS = {
    "the", "and", "for", "day", "with", "from", "into", "madlanga", "commission",
    "order", "ruling", "notice", "application", "statement", "media", "amendment",
    "proclamation", "government", "gazette", "witness", "protection", "camera",
    "public", "hearing", "first", "opening", "address", "remarks", "report",
    "submitted", "use", "resumption", "clarification", "recess",
    "chairperson", "chairpersons", "world", "cup", "interim", "terms",
    "reference", "provincial", "provisional", "final", "adjournment",
    "postponement", "testimony", "appearance", "confidentiality",
    "annexure", "motion", "joint", "advisory", "easter", "sabc",
    "bafana", "legal", "teams", "commencement", "enquiry", "inquiry",
    "judicial", "criminal", "justice", "system", "held", "bridget",
    "mabandla", "college", "in", "on", "of", "at", "to", "no", "by",
    "league", "national", "indian", "cabal", "cartel", "letter",
    "2025", "2026", "september", "october", "november", "december",
    "january", "february", "march", "april", "may", "june", "july",
    "august", "date", "pdf", "doc", "file", "copy", "page", "pages",
    "draft", "agreed", "agreement", "terms", "schedule", "annexure",
    "nov", "sep", "oct", "dec", "jan", "feb", "mar", "apr", "jun", "jul",
}


def extract_entities_from_text(text):
    """Extract entity keywords from a text string using patterns."""
    entities = []
    text_lower = text.lower()
    for org in ORG_PATTERNS:
        if org.lower() in text_lower:
            entities.append(org)
    for loc in LOCATIONS:
        if re.search(r"\b" + re.escape(loc) + r"\b", text, re.IGNORECASE):
            entities.append(loc)
    # Extract capitalized multi-word names from title text
    name_phrases = re.findall(r"([A-Z][a-z]+(?:[\s-]+[A-Z][a-z]+)+)", text)
    for phrase in name_phrases:
        words = phrase.replace("-", " ").split()
        significant = [w for w in words if w.lower() not in STOP_WORDS]
        if len(significant) >= 1:
            name = " ".join(significant)
            if len(name) > 2:
                entities.append(name)
    return sorted(set(entities), key=str.lower)


def build_commission_timeline(conn):
    """Build timeline from commission documents (rulings, applications, statements)."""
    rows = conn.execute(
        "SELECT id, title, category, document_date, file_path "
        "FROM documents ORDER BY document_date"
    ).fetchall()

    timeline = []
    for r in rows:
        title = r["title"] or ""
        category = r["category"] or "other"
        date = r["document_date"] or ""
        if not date:
            continue

        # Clean up title for display
        label = re.sub(r"^\d{4}-\d{2}-\d{2}_", "", title)
        label = label.replace("Madlanga-Commission_", "")
        label = label.replace("_", " ")
        label = re.sub(r" +", " ", label).strip()

        cat_label = {
            "ruling": "Ruling",
            "application": "Application",
            "media_statement": "Media Statement",
            "media": "Media Release",
            "statement": "Statement",
        }.get(category, category.title())

        entities = extract_entities_from_text(label)

        timeline.append(
            {
                "id": r["id"],
                "date": date,
                "title": label[:140],
                "category": category,
                "category_label": cat_label,
                "snippet": "",
                "entities": entities,
                "file_path": r["file_path"] or "",
                "source_type": "document",
            }
        )

    return timeline


def build_witness_timeline(conn):
    """Build timeline from witness testimony grouped by hearing day and speaker."""
    rows = conn.execute(
        """
        SELECT
            h.day_number,
            h.hearing_date,
            h.summary,
            s.canonical_name AS speaker,
            s.role,
            COUNT(DISTINCT ts.id) AS segment_count,
            GROUP_CONCAT(DISTINCT e.entity_value) AS entity_values
        FROM transcript_segments ts
        JOIN hearings h ON h.id = ts.hearing_id
        JOIN speakers s ON s.id = ts.speaker_id
        LEFT JOIN entities e ON e.hearing_id = ts.hearing_id
            AND e.entity_type IN ('organization', 'case_reference', 'exhibit')
        WHERE s.role IN ('witness', 'witness_protected')
        GROUP BY h.day_number, s.canonical_name
        ORDER BY h.day_number, segment_count DESC
        """
    ).fetchall()

    days = defaultdict(list)
    for r in rows:
        entities_str = r["entity_values"] or ""
        top_entities = []
        if entities_str:
            entity_counts = defaultdict(int)
            for e in entities_str.split(","):
                e = e.strip()
                if e and len(e) > 1:
                    entity_counts[e] += 1
            top_entities = sorted(entity_counts, key=entity_counts.get, reverse=True)[:8]

        days[r["day_number"]].append(
            {
                "day": r["day_number"],
                "date": r["hearing_date"] or "",
                "speaker": r["speaker"],
                "role": r["role"],
                "segments": r["segment_count"],
                "summary": (r["summary"] or ""),
                "entities": top_entities,
                "source_type": "testimony",
            }
        )

    return dict(days)


def build_shared_entities(commission_timeline, witness_days):
    """Find entities appearing in both commission documents and witness testimony."""
    commission_entities = set()
    for event in commission_timeline:
        commission_entities.update(e.lower() for e in event.get("entities", []))

    witness_entities = set()
    for day_num, speakers in witness_days.items():
        for spk in speakers:
            witness_entities.update(e.lower() for e in spk.get("entities", []))

    shared = sorted(commission_entities & witness_entities)
    return shared


def build_unique_witnesses(witness_days):
    """Build a sorted list of unique witness names."""
    seen = set()
    witnesses = []
    for day_num, speakers in sorted(witness_days.items()):
        for spk in speakers:
            if spk["speaker"] not in seen:
                seen.add(spk["speaker"])
                witnesses.append(
                    {
                        "name": spk["speaker"],
                        "role": spk["role"],
                        "first_day": day_num,
                    }
                )
    return witnesses


def build_story_map():
    """Build the full story map JSON and save to www directory."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    print("Building commission evidence timeline...")
    commission_timeline = build_commission_timeline(conn)
    print(f"  {len(commission_timeline)} document events")

    print("Building witness testimony timeline...")
    witness_days = build_witness_timeline(conn)
    total_witness_events = sum(len(v) for v in witness_days.values())
    print(f"  {len(witness_days)} hearing days  ({total_witness_events} witness slots)")

    print("Extracting unique witnesses...")
    unique_witnesses = build_unique_witnesses(witness_days)
    print(f"  {len(unique_witnesses)} unique witnesses")

    print("Finding shared entities...")
    shared_entities = build_shared_entities(commission_timeline, witness_days)
    print(f"  {len(shared_entities)} shared entities")

    # Convert witness_days to flat sorted list
    witness_timeline = []
    for day_num in sorted(witness_days.keys()):
        for spk in witness_days[day_num]:
            witness_timeline.append(spk)

    all_entities = set()
    for event in commission_timeline:
        all_entities.update(e.lower() for e in event.get("entities", []))
    for spk in witness_timeline:
        all_entities.update(e.lower() for e in spk.get("entities", []))

    stats = {
        "total_commission_events": len(commission_timeline),
        "total_witness_slots": total_witness_events,
        "total_hearing_days": len(witness_days),
        "total_unique_witnesses": len(unique_witnesses),
        "total_shared_entities": len(shared_entities),
        "date_range": {
            "first": min(
                (e["date"] for e in commission_timeline if e["date"]),
                default="2025-09-17",
            ),
            "last": max(
                (e["date"] for e in commission_timeline if e["date"]),
                default="2026-07-21",
            ),
        },
    }

    output = {
        "commission_timeline": commission_timeline,
        "witness_timeline": witness_timeline,
        "unique_witnesses": unique_witnesses,
        "shared_entities": sorted(shared_entities),
        "all_entities": sorted(all_entities),
        "stats": stats,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\nStory map data saved: {OUTPUT_FILE}")
    kbsize = OUTPUT_FILE.stat().st_size / 1024
    print(f"  Size: {kbsize:.0f} KB")

    conn.close()
    return output


if __name__ == "__main__":
    build_story_map()
