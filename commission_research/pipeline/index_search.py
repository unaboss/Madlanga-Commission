"""
index_search.py — Build SQLite FTS5 full-text search index over transcripts and statements.

Produces: data/commission_research.db  (SQLite database with FTS5 index)
"""

import json
import sqlite3
from pathlib import Path


DATA_DIR  = Path(__file__).resolve().parent.parent / "data"
DB_PATH   = DATA_DIR / "commission_research.db"

INPUT_TRANSCRIPTS_NORM = DATA_DIR / "parsed" / "transcripts_normalized.jsonl"
INPUT_TRANSCRIPTS_RAW  = DATA_DIR / "parsed" / "transcripts.jsonl"
INPUT_STATEMENTS       = DATA_DIR / "parsed" / "statements.jsonl"
INPUT_ENTITIES         = DATA_DIR / "parsed" / "entities.jsonl"
INPUT_HEARINGS_META    = Path(__file__).resolve().parents[2] / "madlanga_downloads" / "metadata" / "hearings.json"
INPUT_DOCUMENTS_META   = Path(__file__).resolve().parents[2] / "madlanga_downloads" / "metadata" / "documents.json"


def build_db():
    """Create the SQLite database with all tables and FTS5 index."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    if DB_PATH.exists():
        DB_PATH.unlink()

    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-20000")  # 20MB cache for bulk insert speed

    # ── Schema ─────────────────────────────────────────────────
    conn.executescript("""
        CREATE TABLE hearings (
            id INTEGER PRIMARY KEY,
            day_number INTEGER NOT NULL,
            hearing_date TEXT NOT NULL,
            title TEXT DEFAULT '',
            summary TEXT DEFAULT '',
            video_url TEXT DEFAULT '',
            location TEXT DEFAULT 'Bridget Mabandla Justice College'
        );

        CREATE TABLE speakers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            canonical_name TEXT NOT NULL UNIQUE,
            role TEXT NOT NULL DEFAULT 'other'
        );

        CREATE TABLE transcript_segments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hearing_id INTEGER REFERENCES hearings(id),
            speaker_id INTEGER REFERENCES speakers(id),
            text TEXT NOT NULL,
            page_number INTEGER DEFAULT 0,
            line_number INTEGER DEFAULT 0,
            line_start INTEGER DEFAULT 0,
            page_end INTEGER DEFAULT 0,
            line_end INTEGER DEFAULT 0
        );

        CREATE TABLE statements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT DEFAULT '',
            stype TEXT DEFAULT 'other',
            hearing_id INTEGER REFERENCES hearings(id),
            author TEXT DEFAULT '',
            full_text TEXT NOT NULL,
            file_path TEXT DEFAULT ''
        );

        CREATE TABLE documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT DEFAULT 'other',
            document_date TEXT DEFAULT '',
            file_path TEXT DEFAULT ''
        );

        CREATE TABLE entities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL DEFAULT 'transcript',
            source_id INTEGER DEFAULT 0,
            entity_type TEXT NOT NULL,
            entity_value TEXT NOT NULL,
            context_text TEXT DEFAULT '',
            hearing_id INTEGER REFERENCES hearings(id),
            speaker_id INTEGER REFERENCES speakers(id),
            page_number INTEGER DEFAULT 0,
            line_start INTEGER DEFAULT 0,
            page_end INTEGER DEFAULT 0,
            line_end INTEGER DEFAULT 0
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
            source,
            source_id UNINDEXED,
            title,
            text,
            date,
            speaker,
            tokenize='porter unicode61'
        );
    """)

    # ── Load hearings metadata ─────────────────────────────────
    print("Loading hearings...")
    hearings_map = {}
    if INPUT_HEARINGS_META.exists():
        hearings = json.loads(INPUT_HEARINGS_META.read_text(encoding="utf-8"))
        for h in hearings:
            conn.execute(
                "INSERT INTO hearings (id, day_number, hearing_date, title, summary, video_url) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (h["day_number"], h["day_number"], h["hearing_date"][:10],
                 h.get("title", ""), h.get("summary", ""), h.get("video_url", ""))
            )
            hearings_map[h["day_number"]] = h
        print(f"  {len(hearings)} hearings loaded")

    # ── Load transcript segments ────────────────────────────────
    print("Loading transcript segments...")
    speaker_map = {}
    speaker_id_counter = 1
    seg_batch = []

    use_norm = INPUT_TRANSCRIPTS_NORM.exists()
    input_file = INPUT_TRANSCRIPTS_NORM if use_norm else INPUT_TRANSCRIPTS_RAW

    if not input_file.exists():
        print(f"  WARNING: No transcript file at {input_file}")
    else:
        seg_count = 0
        with open(input_file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                seg = json.loads(line)

                spk = seg.get("speaker_canonical") or seg.get("speaker", "")
                if spk not in speaker_map:
                    role = seg.get("speaker_role", "other")
                    speaker_map[spk] = speaker_id_counter
                    conn.execute(
                        "INSERT INTO speakers (id, canonical_name, role) VALUES (?, ?, ?)",
                        (speaker_id_counter, spk, role)
                    )
                    speaker_id_counter += 1
                spk_id = speaker_map[spk]

                day = seg.get("day", 0)
                seg_batch.append((day, spk_id, seg["text"],
                                  seg.get("page", 0), seg.get("line", 0),
                                  seg.get("line_start", 0),
                                  seg.get("page_end", seg.get("page", 0)),
                                  seg.get("line_end", 0)))

                if len(seg_batch) >= 10000:
                    conn.executemany(
                        "INSERT INTO transcript_segments "
                        "(hearing_id, speaker_id, text, page_number, line_number, "
                        "line_start, page_end, line_end) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", seg_batch)
                    seg_count += len(seg_batch)
                    seg_batch.clear()
                    print(f"  {seg_count} segments loaded...")

            if seg_batch:
                conn.executemany(
                    "INSERT INTO transcript_segments "
                    "(hearing_id, speaker_id, text, page_number, line_number, "
                    "line_start, page_end, line_end) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", seg_batch)
                seg_count += len(seg_batch)
        print(f"  {seg_count} transcript segments total  ({len(speaker_map)} speakers)")

    # ── Load statements ─────────────────────────────────────────
    print("Loading witness statements...")
    if INPUT_STATEMENTS.exists():
        stmt_batch = []
        stmt_count = 0
        with open(INPUT_STATEMENTS, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                s = json.loads(line)
                hearing_day = s.get("hearing_day", 0)
                stmt_batch.append((
                    s.get("title", ""), s.get("type", "other"),
                    hearing_day, s.get("author", ""),
                    s.get("full_text", ""), s.get("file_path", "")
                ))
                if len(stmt_batch) >= 50:
                    conn.executemany(
                        "INSERT INTO statements (title, stype, hearing_id, author, full_text, file_path) "
                        "VALUES (?, ?, ?, ?, ?, ?)", stmt_batch)
                    stmt_count += len(stmt_batch)
                    stmt_batch.clear()
            if stmt_batch:
                conn.executemany(
                    "INSERT INTO statements (title, stype, hearing_id, author, full_text, file_path) "
                    "VALUES (?, ?, ?, ?, ?, ?)", stmt_batch)
                stmt_count += len(stmt_batch)
        print(f"  {stmt_count} statements loaded")

    # ── Load documents ─────────────────────────────────────────
    print("Loading documents/rulings...")
    if INPUT_DOCUMENTS_META.exists():
        docs = json.loads(INPUT_DOCUMENTS_META.read_text(encoding="utf-8"))
        doc_batch = []
        for d in docs:
            doc_batch.append((
                d.get("title", ""), d.get("category", "other"),
                (d.get("document_date") or "")[:10], d.get("file_path", "")
            ))
        conn.executemany(
            "INSERT INTO documents (title, category, document_date, file_path) VALUES (?, ?, ?, ?)",
            doc_batch)
        print(f"  {len(docs)} documents loaded")

    # ── Load entities ───────────────────────────────────────────
    print("Loading entities...")
    if INPUT_ENTITIES.exists():
        # First pass: collect all statement author names that aren't yet in speaker_map
        with open(INPUT_ENTITIES, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                e = json.loads(line)
                if e.get("source") == "statement":
                    spk = e.get("speaker", "")
                    if spk and spk not in speaker_map:
                        speaker_map[spk] = speaker_id_counter
                        conn.execute(
                            "INSERT INTO speakers (id, canonical_name, role) VALUES (?, ?, ?)",
                            (speaker_id_counter, spk, "witness")
                        )
                        speaker_id_counter += 1

        # Second pass: load entities with correct speaker mapping
        ent_batch = []
        with open(INPUT_ENTITIES, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                e = json.loads(line)
                ent_batch.append((
                    e.get("source", ""), e.get("day", 0),
                    e.get("entity_type", ""), e.get("entity_value", ""),
                    e.get("context", ""), e.get("day", 0),
                    speaker_map.get(e.get("speaker", ""), 0),
                    e.get("page", 0), e.get("line_start", 0),
                    e.get("page_end", e.get("page", 0)), e.get("line_end", 0)
                ))
                if len(ent_batch) >= 5000:
                    conn.executemany(
                        "INSERT INTO entities (source, source_id, entity_type, entity_value, "
                        "context_text, hearing_id, speaker_id, page_number, line_start, "
                        "page_end, line_end) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        ent_batch)
                    ent_batch.clear()
            if ent_batch:
                conn.executemany(
                    "INSERT INTO entities (source, source_id, entity_type, entity_value, "
                    "context_text, hearing_id, speaker_id, page_number, line_start, "
                    "page_end, line_end) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    ent_batch)
        print(f"  {sum(1 for _ in open(INPUT_ENTITIES, encoding='utf-8') if _.strip())} entities loaded")

    # ── Build FTS5 index ────────────────────────────────────────
    print("Building full-text search index...")

    with conn:
        # Index transcript segments
        rows = conn.execute("""
            SELECT ts.rowid, h.day_number, s.canonical_name, ts.text, h.hearing_date
            FROM transcript_segments ts
            JOIN hearings h ON h.id = ts.hearing_id
            JOIN speakers s ON s.id = ts.speaker_id
        """).fetchall()

        fts_batch = []
        for row in rows:
            rowid, day, speaker, text, date = row
            title = f"Day {day} — {speaker}"
            fts_batch.append(("transcript", rowid, title, text, date or "", speaker))
            if len(fts_batch) >= 10000:
                conn.executemany(
                    "INSERT INTO search_index (source, source_id, title, text, date, speaker) "
                    "VALUES (?, ?, ?, ?, ?, ?)", fts_batch)
                fts_batch.clear()
                print(f"  FTS: {len(rows)} transcript segments being indexed...")
        if fts_batch:
            conn.executemany(
                "INSERT INTO search_index (source, source_id, title, text, date, speaker) "
                "VALUES (?, ?, ?, ?, ?, ?)", fts_batch)

        # Index statements
        stmts = conn.execute(
            "SELECT rowid, title, author, full_text, hearing_id FROM statements"
        ).fetchall()
        fts_batch = []
        for row in stmts:
            rowid, title, author, text, hid = row
            date = hearings_map.get(hid, {}).get("hearing_date", "")[:10] if hid else ""
            fts_batch.append(
                ("statement", rowid, title or author or "Statement", text, date, author or "")
            )
            if len(fts_batch) >= 500:
                conn.executemany(
                    "INSERT INTO search_index (source, source_id, title, text, date, speaker) "
                    "VALUES (?, ?, ?, ?, ?, ?)", fts_batch)
                fts_batch.clear()
        if fts_batch:
            conn.executemany(
                "INSERT INTO search_index (source, source_id, title, text, date, speaker) "
                "VALUES (?, ?, ?, ?, ?, ?)", fts_batch)

    print("  FTS5 index built")

    # ── Indexes ─────────────────────────────────────────────────
    conn.executescript("""
        CREATE INDEX IF NOT EXISTS idx_segments_hearing ON transcript_segments(hearing_id);
        CREATE INDEX IF NOT EXISTS idx_segments_speaker ON transcript_segments(speaker_id);
        CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type);
        CREATE INDEX IF NOT EXISTS idx_entities_value ON entities(entity_value);
        CREATE INDEX IF NOT EXISTS idx_entities_hearing ON entities(hearing_id);
        CREATE INDEX IF NOT EXISTS idx_entities_speaker ON entities(speaker_id);
        CREATE INDEX IF NOT EXISTS idx_statements_hearing ON statements(hearing_id);
        CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(category);
    """)

    # ── Summary ─────────────────────────────────────────────────
    counts = {}
    for table in ["hearings", "speakers", "transcript_segments",
                  "statements", "documents", "entities"]:
        counts[table] = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    fts_count = conn.execute("SELECT COUNT(*) FROM search_index").fetchone()[0]

    conn.close()

    print(f"\n{'='*50}")
    print("Database built successfully!")
    for table, count in counts.items():
        print(f"  {table:25s}: {count:6d}")
    print(f"  {'search_index (FTS5)':25s}: {fts_count:6d}")
    print(f"  Database: {DB_PATH}")
    print(f"  Size: {DB_PATH.stat().st_size / (1024*1024):.1f} MB")


if __name__ == "__main__":
    build_db()
