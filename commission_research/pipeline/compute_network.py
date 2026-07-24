"""
compute_network.py — Build network graph JSON for the Shiny dashboard.
Computes nodes (speakers) and edges (relationships) from the database.
"""

import sqlite3
import json
import re
from pathlib import Path
from collections import Counter, defaultdict

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "commission_research.db"
OUT_DIR = Path(__file__).resolve().parent.parent / "app" / "www"


def get_search_term(name: str) -> str:
    """Extract the searchable term from a witness name.
    For protected witnesses: 'witness b', 'witness c', etc.
    For others: just the surname (last word)."""
    clean = re.sub(r'\s*\(.*?\)\s*', '', name).strip()
    if clean.startswith("Witness "):
        return clean.lower()
    parts = clean.split()
    return parts[-1].lower() if parts else ""


def build_network():
    """Build network graph data and save as JSON."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    # ── Nodes ───────────────────────────────────────────────────
    print("Building nodes...")
    rows = conn.execute("""
        SELECT s.id, s.canonical_name, s.role, COUNT(ts.id) AS segments,
               COUNT(DISTINCT ts.hearing_id) AS hearing_days,
               MIN(h.hearing_date) AS first_date,
               MAX(h.hearing_date) AS last_date
        FROM speakers s
        JOIN transcript_segments ts ON ts.speaker_id = s.id
        JOIN hearings h ON h.id = ts.hearing_id
        WHERE s.role IN ('witness', 'witness_protected')
        GROUP BY s.id
    """).fetchall()

    # Build witness lookup: search_term -> (name, id)
    witness_terms = {}
    for r in rows:
        term = get_search_term(r["canonical_name"])
        witness_terms[term] = (r["canonical_name"], r["id"])

    # ── Edges: who-mentions-whom in testimony ──────────────────
    print("Building edges from name mentions...")
    segments = conn.execute("""
        SELECT ts.speaker_id, ts.text
        FROM transcript_segments ts
        JOIN speakers s ON s.id = ts.speaker_id
        WHERE s.role IN ('witness', 'witness_protected')
    """).fetchall()

    mention_counts = defaultdict(int)
    for seg in segments:
        text = seg["text"].lower()
        speaker_id = seg["speaker_id"]
        for term, (name, w_id) in witness_terms.items():
            if speaker_id == w_id:
                continue
            if term in text:
                mention_counts[(speaker_id, w_id)] += 1

    edges = []
    max_weight = max(mention_counts.values()) if mention_counts else 1
    for (from_id, to_id), count in mention_counts.items():
        if count < 3:
            continue
        thickness = 1 + (count / max_weight) * 5
        edges.append({
            "from": from_id,
            "to": to_id,
            "value": count,
            "title": f"Mentioned {count} times in testimony",
            "width": thickness,
            "arrows": {"to": {"enabled": True, "scaleFactor": 0.5}},
            "color": {"opacity": 0.3 + (count / max_weight) * 0.5},
        })

    # Compute degree centrality from mentions
    in_degree = Counter()
    out_degree = Counter()
    for (from_id, to_id), count in mention_counts.items():
        out_degree[from_id] += 1
        in_degree[to_id] += 1

    role_colors = {
        "witness":            {"bg": "#90EE90", "border": "#228B22", "highlight": "#C1FFC1"},
        "witness_protected":  {"bg": "#FF6347", "border": "#8B0000", "highlight": "#FF7F50"},
    }

    max_segments = max(r["segments"] for r in rows) or 1
    max_in = max(in_degree.values()) if in_degree else 1
    max_out = max(out_degree.values()) if out_degree else 1

    nodes = []
    for r in rows:
        rc = role_colors.get(r["role"], role_colors["witness"])
        name = r["canonical_name"]
        title = extract_title(name)
        sid = r["id"]
        seg_norm = r["segments"] / max_segments
        in_norm = in_degree.get(sid, 0) / max_in
        out_norm = out_degree.get(sid, 0) / max_out
        # Size: 30% segments, 30% how many people they name, 40% how many people name them
        size = 10 + (seg_norm * 0.3 + out_norm * 0.3 + in_norm * 0.4) * 50
        total_mentions = out_degree.get(sid, 0) + in_degree.get(sid, 0)

        m_in = in_degree.get(sid, 0)
        m_out = out_degree.get(sid, 0)

        nodes.append({
            "id": sid,
            "label": name,
            "title": f"<b>{name}</b><br>Role: {r['role']}<br>"
                     f"Segments: {r['segments']:,}<br>"
                     f"Days: {r['hearing_days']}<br>"
                     f"Mentions others: {m_out}<br>"
                     f"Mentioned by others: {m_in}",
            "group": r["role"],
            "value": r["segments"],
            "size": round(size, 1),
            "role": r["role"],
            "rank": title,
            "segments": r["segments"],
            "days": r["hearing_days"],
            "centrality": total_mentions,
            "color": {
                "background": rc["bg"],
                "border": rc["border"],
                "highlight": {"background": rc["highlight"], "border": rc["border"]},
            },
            "shape": "dot",
            "font": {"size": 10 + (r["segments"] / max_segments) * 8},
        })


    # ── Role groupings ──────────────────────────────────────────
    print("Building role groupings...")
    roles_data = {}
    for r in rows:
        role = r["role"]
        if role not in roles_data:
            roles_data[role] = []
        roles_data[role].append({
            "name": r["canonical_name"],
            "rank": extract_title(r["canonical_name"]),
            "segments": r["segments"],
            "days": r["hearing_days"],
            "first": r["first_date"],
            "last": r["last_date"],
        })

    # ── Stats ───────────────────────────────────────────────────
    stats = {
        "total_hearings": conn.execute("SELECT COUNT(*) FROM hearings").fetchone()[0],
        "total_speakers": conn.execute(
            "SELECT COUNT(*) FROM speakers WHERE role IN ('witness', 'witness_protected')"
        ).fetchone()[0],
        "total_segments": conn.execute(
            "SELECT COUNT(*) FROM transcript_segments ts "
            "JOIN speakers s ON s.id = ts.speaker_id "
            "WHERE s.role IN ('witness', 'witness_protected')"
        ).fetchone()[0],
        "total_statements": conn.execute("SELECT COUNT(*) FROM statements").fetchone()[0],
        "total_documents": conn.execute("SELECT COUNT(*) FROM documents").fetchone()[0],
        "total_entities": conn.execute("SELECT COUNT(*) FROM entities").fetchone()[0],
        "date_range": {
            "first": conn.execute(
                "SELECT MIN(h.hearing_date) FROM transcript_segments ts "
                "JOIN speakers s ON s.id = ts.speaker_id "
                "JOIN hearings h ON h.id = ts.hearing_id "
                "WHERE s.role IN ('witness', 'witness_protected')"
            ).fetchone()[0] or "",
            "last": conn.execute(
                "SELECT MAX(h.hearing_date) FROM transcript_segments ts "
                "JOIN speakers s ON s.id = ts.speaker_id "
                "JOIN hearings h ON h.id = ts.hearing_id "
                "WHERE s.role IN ('witness', 'witness_protected')"
            ).fetchone()[0] or "",
        },
    }

    # ── Top entity connections (who-mentions-whom) ───────────────
    print("Building entity mentions...")
    top_entities = conn.execute("""
        SELECT entity_value, entity_type, COUNT(*) AS cnt
        FROM entities
        WHERE entity_type IN ('organization', 'case_reference', 'location')
        GROUP BY entity_value
        ORDER BY cnt DESC
        LIMIT 40
    """).fetchall()

    output = {
        "nodes": nodes,
        "edges": edges,
        "roles": roles_data,
        "stats": stats,
        "top_entities": [{"value": e["entity_value"], "type": e["entity_type"],
                          "count": e["cnt"]} for e in top_entities],
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / "network_data.json"
    out_path.write_text(json.dumps(output, ensure_ascii=False), encoding="utf-8")

    print(f"\nNetwork data saved: {out_path}")
    print(f"  Nodes: {len(nodes)}")
    print(f"  Edges: {len(edges)}")
    print(f"  Size: {out_path.stat().st_size / 1024:.0f} KB")

    conn.close()
    return output


def extract_title(name):
    """Extract rank/title from a canonical name."""
    prefixes = [
        "Justice", "Adv", "Lt Gen", "Maj Gen", "Brigadier", "Colonel",
        "Lt Col", "Captain", "Major", "Sergeant", "Warrant Officer",
        "WO", "Commissioner", "Minister", "Deputy Chief", "Chief",
        "Director", "Assistant Director", "Asst Dir", "Mr", "Ms", "Dr",
        "General", "Brig",
    ]
    for p in sorted(prefixes, key=len, reverse=True):
        if name.startswith(p):
            return p
    if name.startswith("Witness"):
        return "Protected Witness"
    return "Other"


if __name__ == "__main__":
    build_network()
