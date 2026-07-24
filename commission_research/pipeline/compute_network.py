"""
compute_network.py — Build network graph JSON for the Shiny dashboard.
Computes nodes (speakers) and edges (relationships) from the database.
"""

import sqlite3
import json
from pathlib import Path
from collections import Counter

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "commission_research.db"
OUT_DIR = Path(__file__).resolve().parent.parent / "app" / "www"


def build_network():
    """Build network graph data and save as JSON."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    # ── Edges first (needed for centrality) ──────────────────────
    print("Building edges...")
    edge_rows = conn.execute("""
        SELECT a.speaker_id AS from_id, b.speaker_id AS to_id,
               COUNT(*) AS weight,
               GROUP_CONCAT(DISTINCT a.hearing_id) AS shared_days
        FROM transcript_segments a
        JOIN transcript_segments b ON a.hearing_id = b.hearing_id
                                   AND a.speaker_id < b.speaker_id
        JOIN speakers sa ON sa.id = a.speaker_id
                         AND sa.role IN ('witness', 'witness_protected')
        JOIN speakers sb ON sb.id = b.speaker_id
                         AND sb.role IN ('witness', 'witness_protected')
        WHERE a.speaker_id != b.speaker_id
        GROUP BY a.speaker_id, b.speaker_id
        HAVING weight >= 3
        ORDER BY weight DESC
        LIMIT 3000
    """).fetchall()

    # Compute degree centrality (unique connections per node)
    degree_counts = Counter()
    for e in edge_rows:
        degree_counts[e["from_id"]] += 1
        degree_counts[e["to_id"]] += 1

    edges = []
    max_weight = max(r["weight"] for r in edge_rows) if edge_rows else 1
    for r in edge_rows:
        thickness = 1 + (r["weight"] / max_weight) * 5
        edges.append({
            "from": r["from_id"],
            "to": r["to_id"],
            "value": r["weight"],
            "title": f"Co-occur on {r['shared_days']} hearing days<br>"
                     f"{r['weight']} shared segments",
            "width": thickness,
            "color": {"opacity": 0.3 + (r["weight"] / max_weight) * 0.5},
        })


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
        ORDER BY segments DESC
    """).fetchall()

    role_colors = {
        "witness":            {"bg": "#90EE90", "border": "#228B22", "highlight": "#C1FFC1"},
        "witness_protected":  {"bg": "#FF6347", "border": "#8B0000", "highlight": "#FF7F50"},
    }

    max_segments = max(r["segments"] for r in rows)
    max_degree = max(degree_counts.values()) if degree_counts else 1

    nodes = []
    for r in rows:
        rc = role_colors.get(r["role"], role_colors["witness"])
        name = r["canonical_name"]
        title = extract_title(name)
        sid = r["id"]
        seg_norm = r["segments"] / max_segments
        deg_norm = degree_counts.get(sid, 0) / max_degree
        size = 10 + (seg_norm * 0.4 + deg_norm * 0.6) * 50

        nodes.append({
            "id": sid,
            "label": name,
            "title": f"<b>{name}</b><br>Role: {r['role']}<br>"
                     f"Segments: {r['segments']:,}<br>"
                     f"Days: {r['hearing_days']}<br>"
                     f"First: {r['first_date']}<br>Last: {r['last_date']}",
            "group": r["role"],
            "value": r["segments"],
            "size": round(size, 1),
            "role": r["role"],
            "rank": title,
            "segments": r["segments"],
            "days": r["hearing_days"],
            "centrality": degree_counts.get(sid, 0),
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
            "first": rows[-1]["first_date"] if rows else "",
            "last": rows[0]["first_date"] if rows else "",
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
