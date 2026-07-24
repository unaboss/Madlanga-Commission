"""
compute_network.py — Build bipartite Case Web graph for the Shiny dashboard.
Nodes: Persons (witnesses) + Case Entities (orgs, cases, exhibits, locations, money).
Edges: Person -> Entity (witness mentioned this entity in testimony).
"""

import sqlite3
import json
import re
from pathlib import Path
from collections import Counter, defaultdict

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "commission_research.db"
OUT_DIR = Path(__file__).resolve().parent.parent / "app" / "www"

ENTITY_TYPES = ("organization", "case_reference", "exhibit", "location", "money")
MIN_EDGE_WEIGHT = 3
MIN_ENTITY_TOTAL = 5
MAX_NODES = 120
MAX_EDGES = 400

# Colors by node group
PERSON_COLORS = {
    "witness":            {"background": "#90EE90", "border": "#228B22", "highlight": {"background": "#C1FFC1", "border": "#228B22"}},
    "witness_protected":  {"background": "#FF6347", "border": "#8B0000", "highlight": {"background": "#FF7F50", "border": "#8B0000"}},
}
ENTITY_COLORS = {
    "organization":      {"background": "#FFD700", "border": "#B8860B", "highlight": {"background": "#FFEC8B", "border": "#B8860B"}},
    "case_reference":    {"background": "#4FC3F7", "border": "#0288D1", "highlight": {"background": "#81D4FA", "border": "#0288D1"}},
    "exhibit":           {"background": "#009688", "border": "#004D40", "highlight": {"background": "#4DB6AC", "border": "#004D40"}},
    "location":          {"background": "#CE93D8", "border": "#7B1FA2", "highlight": {"background": "#E1BEE7", "border": "#7B1FA2"}},
    "money":             {"background": "#FFB74D", "border": "#E65100", "highlight": {"background": "#FFCC80", "border": "#E65100"}},
}


def extract_title(name):
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


def build_network():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    # ── 1. Person nodes ────────────────────────────────────────
    print("Building person nodes...")
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

    person_nodes = []
    person_ids = []
    max_segments = max(r["segments"] for r in rows) or 1
    for r in rows:
        sid = r["id"]
        person_ids.append(sid)
        seg_norm = r["segments"] / max_segments
        size = 10 + seg_norm * 30
        person_nodes.append({
            "id": sid,
            "label": r["canonical_name"],
            "title": f"<b>{r['canonical_name']}</b><br>Role: {r['role']}<br>"
                     f"Segments: {r['segments']:,}<br>Days: {r['hearing_days']}",
            "nodeType": "person",
            "group": r["role"],
            "value": r["segments"],
            "size": round(size, 1),
            "role": r["role"],
            "rank": extract_title(r["canonical_name"]),
            "segments": r["segments"],
            "days": r["hearing_days"],
            "color": PERSON_COLORS.get(r["role"], PERSON_COLORS["witness"]),
            "shape": "dot",
            "font": {"size": 10 + seg_norm * 8},
        })

    # ── 2. Entity nodes ────────────────────────────────────────
    print("Building entity nodes...")
    entity_rows = conn.execute("""
        SELECT entity_value, entity_type, COUNT(*) AS total_count,
               COUNT(DISTINCT speaker_id) AS witness_count
        FROM entities
        WHERE entity_type IN ('organization', 'case_reference', 'exhibit', 'location', 'money')
          AND speaker_id IN ({})
        GROUP BY entity_value
        HAVING total_count >= ?
        ORDER BY total_count DESC
        LIMIT 200
    """.format(",".join("?" for _ in person_ids)), [*person_ids, MIN_ENTITY_TOTAL]).fetchall()

    max_entity_count = max(r["total_count"] for r in entity_rows) if entity_rows else 1
    entity_nodes = []
    entity_map = {}   # entity_value -> node_id
    entity_id_counter = 1001
    for r in entity_rows:
        eid = -entity_id_counter
        entity_id_counter += 1
        entity_map[r["entity_value"]] = eid
        norm = r["total_count"] / max_entity_count
        size = 10 + norm * 30
        ec = ENTITY_COLORS.get(r["entity_type"], ENTITY_COLORS["organization"])
        entity_nodes.append({
            "id": eid,
            "label": r["entity_value"],
            "title": f"<b>{r['entity_value']}</b><br>Type: {r['entity_type']}<br>"
                     f"Mentions: {r['total_count']:,}<br>Witnesses: {r['witness_count']}",
            "nodeType": "entity",
            "entityType": r["entity_type"],
            "group": r["entity_type"],
            "value": r["total_count"],
            "size": round(size, 1),
            "mentionCount": r["total_count"],
            "witnessCount": r["witness_count"],
            "color": ec,
            "shape": "dot",
            "font": {"size": 10 + norm * 8},
        })

    # ── 3. Edges: person -> entity ──────────────────────────────
    print("Building edges...")
    edge_rows = conn.execute("""
        SELECT e.speaker_id, e.entity_value, e.entity_type, COUNT(*) AS cnt
        FROM entities e
        WHERE e.speaker_id IN ({})
          AND e.entity_type IN ('organization', 'case_reference', 'exhibit', 'location', 'money')
          AND e.entity_value IN ({})
        GROUP BY e.speaker_id, e.entity_value
        HAVING cnt >= ?
        ORDER BY cnt DESC
        LIMIT 600
    """.format(
        ",".join("?" for _ in person_ids),
        ",".join("?" for _ in entity_map.keys())
    ), [*person_ids, *entity_map.keys(), MIN_EDGE_WEIGHT]).fetchall()

    # Build lookup: person_id -> {entity_value -> count} for edge detail
    person_entity_counts = defaultdict(dict)
    edges = []
    max_edge_weight = max(r["cnt"] for r in edge_rows) if edge_rows else 1
    for r in edge_rows:
        pid = r["speaker_id"]
        eid = entity_map.get(r["entity_value"])
        if eid is None:
            continue
        cnt = r["cnt"]
        person_entity_counts[pid][r["entity_value"]] = cnt
        thickness = 1 + (cnt / max_edge_weight) * 4
        edges.append({
            "from": pid,
            "to": eid,
            "value": cnt,
            "title": f"Mentioned '{r['entity_value']}' {cnt} times",
            "width": round(thickness, 1),
            "entityValue": r["entity_value"],
            "entityType": r["entity_type"],
        })

    # ── 4. Boost person node sizes by entity diversity ─────────
    for pn in person_nodes:
        pid = pn["id"]
        ent_count = len(person_entity_counts.get(pid, {}))
        pn["entityCount"] = ent_count
        # Boost size slightly for witnesses who named many entities
        pn["size"] = round(pn["size"] + min(ent_count * 0.3, 5), 1)
        # Update title to include entity naming info
        pn["title"] = pn["title"].replace("</b><br>", "</b><br>"
            f"Entities named: {ent_count}<br>")

    # ── 5. Assemble ─────────────────────────────────────────────
    all_nodes = person_nodes + entity_nodes

    # Limit to top N nodes and their edges for the mini network
    sorted_nodes = sorted(all_nodes, key=lambda n: n.get("value", 0), reverse=True)
    top_node_ids = set(n["id"] for n in sorted_nodes[:MAX_NODES])
    top_edges = [e for e in edges if e["from"] in top_node_ids and e["to"] in top_node_ids][:MAX_EDGES]

    # ── 6. Role groupings (person-only) ─────────────────────────
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

    # ── 7. Stats ────────────────────────────────────────────────
    total_entities = sum(n.get("nodeType") == "entity" for n in all_nodes)
    stats = {
        "total_hearings": conn.execute("SELECT COUNT(*) FROM hearings").fetchone()[0],
        "total_speakers": len(person_nodes),
        "total_segments": conn.execute(
            "SELECT COUNT(*) FROM transcript_segments ts "
            "JOIN speakers s ON s.id = ts.speaker_id "
            "WHERE s.role IN ('witness', 'witness_protected')"
        ).fetchone()[0],
        "total_entities": total_entities,
        "total_mentions": conn.execute("SELECT COUNT(*) FROM entities").fetchone()[0],
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

    # ── 8. Output ──────────────────────────────────────────────
    top_entities_data = [
        {"value": r["entity_value"], "type": r["entity_type"], "count": r["total_count"]}
        for r in entity_rows[:40]
    ]

    output = {
        "nodes": all_nodes,
        "edges": edges,
        "roles": roles_data,
        "stats": stats,
        "top_entities": top_entities_data,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / "network_data.json"
    out_path.write_text(json.dumps(output, ensure_ascii=False), encoding="utf-8")

    print(f"\nNetwork data saved: {out_path}")
    print(f"  Person nodes: {len(person_nodes)}")
    print(f"  Entity nodes: {len(entity_nodes)}")
    print(f"  Edges: {len(edges)}")
    print(f"  Top nodes shown: {min(len(all_nodes), MAX_NODES)}")
    print(f"  Size: {out_path.stat().st_size / 1024:.0f} KB")

    conn.close()
    return output


if __name__ == "__main__":
    build_network()
