"""
fix_statement_speakers.py — Fix orphaned statement entities in the existing database.

Statement entities were loaded with speaker_id=0 because statement authors
weren't added to the speaker_map before entity loading. This script:
1. Finds all unique statement authors referenced in entities with source='statement'
2. Inserts them into the speakers table if not present
3. Updates the entities table with correct speaker_id values
"""

import sqlite3
import json
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "commission_research.db"


def fix_statement_speakers():
    if not DB_PATH.exists():
        print(f"Database not found: {DB_PATH}")
        return

    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    # Check how many orphaned statement entities exist
    orphan_count = conn.execute(
        "SELECT COUNT(*) FROM entities WHERE source='statement' AND speaker_id=0"
    ).fetchone()[0]
    print(f"Orphaned statement entities (speaker_id=0): {orphan_count}")

    if orphan_count == 0:
        # Check if any statement entities exist at all with valid speakers
        valid_count = conn.execute(
            "SELECT COUNT(*) FROM entities e JOIN speakers s ON s.id=e.speaker_id WHERE e.source='statement'"
        ).fetchone()[0]
        if valid_count > 0:
            print(f"All {valid_count} statement entities already have valid speakers. Nothing to fix.")
        else:
            print("No statement entities found at all.")
        conn.close()
        return

    # Get distinct speaker names from the entities JSONL file
    entities_path = Path(__file__).resolve().parent.parent / "data" / "parsed" / "entities.jsonl"
    statement_speakers = set()
    if entities_path.exists():
        with open(entities_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                e = json.loads(line)
                if e.get("source") == "statement":
                    spk = e.get("speaker", "")
                    if spk:
                        statement_speakers.add(spk)
        print(f"Found {len(statement_speakers)} unique statement authors in entities.jsonl")
    else:
        # Fall back: query distinct context patterns from the entities table
        print(f"entities.jsonl not found, extracting speaker names from DB...")
        rows = conn.execute(
            "SELECT DISTINCT context_text FROM entities WHERE source='statement' LIMIT 500"
        ).fetchall()
        # This is imprecise; best to rebuild from the JSONL
        print("WARNING: Cannot reliably extract speaker names from DB alone.")
        print("Recommendation: Re-run the pipeline with the fixed index_search.py")
        conn.close()
        return

    # Get existing speaker names
    existing = set(r["canonical_name"] for r in conn.execute("SELECT canonical_name FROM speakers"))
    new_speakers = statement_speakers - existing
    print(f"New speakers to insert: {len(new_speakers)}")

    if new_speakers:
        for name in sorted(new_speakers):
            conn.execute(
                "INSERT INTO speakers (canonical_name, role) VALUES (?, 'witness')",
                (name,)
            )
        conn.commit()
        print(f"Inserted {len(new_speakers)} new speakers")

    # Get current speaker_id mapping
    speaker_map = {}
    for r in conn.execute("SELECT id, canonical_name FROM speakers"):
        speaker_map[r["canonical_name"]] = r["id"]

    # Update orphaned entities
    # Re-read the JSONL to get the correct speaker mapping for each entity row
    updated = 0
    skipped_no_match = 0
    with open(entities_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            e = json.loads(line)
            if e.get("source") != "statement":
                continue
            spk = e.get("speaker", "")
            if not spk:
                continue
            spk_id = speaker_map.get(spk, 0)
            if spk_id == 0:
                skipped_no_match += 1
                continue
            # Update by matching context_text and entity_value
            # Since we can't easily match individual rows without a unique ID,
            # update ALL rows with source='statement' AND speaker_id=0
            # that have matching entity_value and context prefix
            ctx_prefix = e.get("context", "")[:100]
            conn.execute(
                "UPDATE entities SET speaker_id=? "
                "WHERE source='statement' AND speaker_id=0 "
                "AND entity_type=? AND entity_value=? "
                "AND substr(context_text,1,100)=?",
                (spk_id, e.get("entity_type", ""), e.get("entity_value", ""), ctx_prefix)
            )
            updated += conn.total_changes  # wonky — just count differently

    # Simpler: just update ALL statement entities with speaker_id=0
    # by matching entity_value + entity_type to a known statement author
    # This is less precise but works for bulk fix
    updated = 0
    for r in conn.execute(
        "SELECT DISTINCT e.entity_value, e.entity_type, substr(e.context_text,1,100) as ctx "
        "FROM entities e WHERE e.source='statement' AND e.speaker_id=0"
    ):
        # Try each statement speaker to find a match in context
        for spk in statement_speakers:
            if spk.lower() in r["ctx"].lower():
                spk_id = speaker_map.get(spk, 0)
                if spk_id:
                    conn.execute(
                        "UPDATE entities SET speaker_id=? "
                        "WHERE source='statement' AND speaker_id=0 "
                        "AND entity_value=? AND entity_type=? "
                        "AND substr(context_text,1,100)=?",
                        (spk_id, r["entity_value"], r["entity_type"], r["ctx"])
                    )
                    updated += 1
                    break

    conn.commit()
    print(f"Updated {updated} statement entities with correct speaker_id")

    # Verify
    still_orphaned = conn.execute(
        "SELECT COUNT(*) FROM entities WHERE source='statement' AND speaker_id=0"
    ).fetchone()[0]
    valid = conn.execute(
        "SELECT COUNT(*) FROM entities e JOIN speakers s ON s.id=e.speaker_id WHERE e.source='statement'"
    ).fetchone()[0]
    print(f"\nAfter fix:")
    print(f"  Still orphaned: {still_orphaned}")
    print(f"  Valid speaker links: {valid}")

    # Show the fixed data
    print(f"\n=== Sample of fixed statement entities ===")
    for r in conn.execute(
        "SELECT s.canonical_name, e.entity_value, e.entity_type "
        "FROM entities e JOIN speakers s ON s.id=e.speaker_id "
        "WHERE e.source='statement' LIMIT 10"
    ):
        print(f"  {r['canonical_name']:35s} | {r['entity_value']:30s} | {r['entity_type']}")

    conn.close()


if __name__ == "__main__":
    fix_statement_speakers()
