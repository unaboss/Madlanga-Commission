"""
compute_network.py — Build bipartite Case Web graph for the Shiny dashboard.
Nodes: Persons (witnesses) + Case Entities (orgs, cases, exhibits, locations, money).
Edges: Person -> Entity (witness mentioned this entity in testimony).
"""

import sqlite3
import json
import re
import math
import random
from pathlib import Path
from collections import Counter, defaultdict

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "commission_research.db"
OUT_DIR = Path(__file__).resolve().parent.parent / "app" / "www"

ENTITY_TYPES = ("organization",)
ENTITY_TYPES_STR = "'organization'"
MIN_EDGE_WEIGHT = 3
MIN_ENTITY_TOTAL = 5
MAX_NODES = 120
MAX_EDGES = 400

# Colors by node group
PERSON_COLORS = {
    "witness":            {"background": "#E74C3C", "border": "#C0392B", "highlight": {"background": "#FF6B6B", "border": "#C0392B"}},
    "witness_protected":  {"background": "#C0392B", "border": "#999999", "highlight": {"background": "#FF6B6B", "border": "#999999"}},
}
ENTITY_COLORS = {
    "organization":      {"background": "#999999", "border": "#666666", "highlight": {"background": "#BBBBBB", "border": "#666666"}},
    "case_reference":    {"background": "#999999", "border": "#666666", "highlight": {"background": "#BBBBBB", "border": "#666666"}},
    "exhibit":           {"background": "#999999", "border": "#666666", "highlight": {"background": "#BBBBBB", "border": "#666666"}},
    "location":          {"background": "#999999", "border": "#666666", "highlight": {"background": "#BBBBBB", "border": "#666666"}},
    "money":             {"background": "#999999", "border": "#666666", "highlight": {"background": "#BBBBBB", "border": "#666666"}},
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


def get_search_term(name: str) -> str:
    """Extract the searchable term from a witness name."""
    clean = re.sub(r'\s*\(.*?\)\s*', '', name).strip()
    if clean.startswith("Witness "):
        return clean.lower()
    parts = clean.split()
    return parts[-1].lower() if parts else ""


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
        size = 25  # uniform size for all witnesses
        person_nodes.append({
            "id": sid,
            "label": r["canonical_name"],
            "title": f"<b>{r['canonical_name']}</b><br>Role: {r['role']}<br>"
                     f"Segments: {r['segments']:,}<br>Days: {r['hearing_days']}",
            "nodeType": "person",
            "group": r["role"],
            "value": r["segments"],
            "size": size,
            "role": r["role"],
            "rank": extract_title(r["canonical_name"]),
            "segments": r["segments"],
            "days": r["hearing_days"],
            "color": PERSON_COLORS.get(r["role"], PERSON_COLORS["witness"]),
            "shape": "dot",
            "borderWidth": 3 if r["role"] == "witness_protected" else 1,
            "font": {"size": 10 + seg_norm * 8},
        })

    # ── 1b. Count how many times each witness was named by others
    print("Computing witness mention counts...")
    witness_surnames = {r["id"]: get_search_term(r["canonical_name"]) for r in rows}
    segments_all = conn.execute("""
        SELECT ts.speaker_id, ts.text
        FROM transcript_segments ts
        JOIN speakers s ON s.id = ts.speaker_id
        WHERE s.role IN ('witness', 'witness_protected')
    """).fetchall()
    mentioned_count = Counter()
    for seg in segments_all:
        text_lower = seg["text"].lower()
        speaker_id = seg["speaker_id"]
        for wid, term in witness_surnames.items():
            if wid != speaker_id and term in text_lower:
                mentioned_count[wid] += 1
    for pn in person_nodes:
        pn["mentionedCount"] = mentioned_count.get(pn["id"], 0)

    # ── 2. Entity nodes ────────────────────────────────────────
    print("Building entity nodes...")
    entity_rows = conn.execute("""
        SELECT entity_value, entity_type, COUNT(*) AS total_count,
               COUNT(DISTINCT speaker_id) AS witness_count
        FROM entities
        WHERE entity_type IN ({})
          AND speaker_id IN ({})
        GROUP BY entity_value
        HAVING total_count >= ?
        ORDER BY total_count DESC
        LIMIT 200
    """.format(ENTITY_TYPES_STR, ",".join("?" for _ in person_ids)), [*person_ids, MIN_ENTITY_TOTAL]).fetchall()

    entity_nodes = []
    entity_map = {}   # entity_value -> node_id
    entity_id_counter = 1001
    for r in entity_rows:
        eid = -entity_id_counter
        entity_id_counter += 1
        entity_map[r["entity_value"]] = eid
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
            "size": 50,
            "mentionCount": r["total_count"],
            "witnessCount": r["witness_count"],
            "color": ec,
            "shape": "dot",
            "font": {"size": 14},
        })

    # ── 3. Edges: person -> entity ──────────────────────────────
    print("Building edges...")
    edge_rows = conn.execute("""
        SELECT e.speaker_id, e.entity_value, e.entity_type, COUNT(*) AS cnt
        FROM entities e
        WHERE e.speaker_id IN ({spk})
          AND e.entity_type IN ({typ})
          AND e.entity_value IN ({val})
        GROUP BY e.speaker_id, e.entity_value
        HAVING cnt >= ?
        ORDER BY cnt DESC
        LIMIT 600
    """.format(
        spk = ",".join("?" for _ in person_ids),
        typ = ENTITY_TYPES_STR,
        val = ",".join("?" for _ in entity_map.keys())
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

    # ── 4a. Entity-to-entity edges (shared witnesses) ──────────
    print("Building entity-to-entity edges...")
    ee_rows = conn.execute("""
        SELECT e1.entity_value AS from_val, e2.entity_value AS to_val,
               COUNT(DISTINCT e1.speaker_id) AS shared_wits
        FROM entities e1
        JOIN entities e2 ON e1.speaker_id = e2.speaker_id
                        AND e1.entity_value < e2.entity_value
        WHERE e1.entity_type IN ({})
          AND e2.entity_type IN ({})
          AND e1.entity_value IN ({})
          AND e2.entity_value IN ({})
        GROUP BY e1.entity_value, e2.entity_value
        HAVING shared_wits >= 3
        ORDER BY shared_wits DESC
        LIMIT 200
    """.format(
        ",".join("?" for _ in ENTITY_TYPES),
        ",".join("?" for _ in ENTITY_TYPES),
        ",".join("?" for _ in entity_map.keys()),
        ",".join("?" for _ in entity_map.keys())
    ), [*ENTITY_TYPES, *ENTITY_TYPES, *entity_map.keys(), *entity_map.keys()]).fetchall()

    for r in ee_rows:
        from_eid = entity_map.get(r["from_val"])
        to_eid = entity_map.get(r["to_val"])
        if from_eid is None or to_eid is None:
            continue
        edges.append({
            "from": from_eid,
            "to": to_eid,
            "value": max(1, int(math.sqrt(r["shared_wits"]))),  # thin, but still scales with count
            "title": f"Connected by {r['shared_wits']} shared witnesses",
            "width": 1,
            "dashes": True,
            "color": {"color": "#555555", "opacity": 0.5},
        })

    # ── 4b. Track entity diversity per person ──────────────────
    for pn in person_nodes:
        pid = pn["id"]
        ent_count = len(person_entity_counts.get(pid, {}))
        pn["entityCount"] = ent_count
        # Update title to include entity naming info
        pn["title"] = pn["title"].replace("</b><br>", "</b><br>"
            f"Entities named: {ent_count}<br>")

    # ── 5. Assemble (round-table entity ordering) ──────────────
    all_nodes = person_nodes + entity_nodes

    # Build entity->witness connectivity map (who connects to this entity)
    entity_witnesses = defaultdict(set)
    for e in edges:
        fid, tid = e["from"], e["to"]
        if fid > 0 and tid < 0:      # person -> entity edge
            entity_witnesses[tid].add(fid)

    # Initial barycenter sort based on witness connections
    eids_ordered = []
    if entity_witnesses:
        remaining = set(entity_witnesses.keys())
        first = max(remaining, key=lambda eid: len(entity_witnesses[eid]))
        eids_ordered.append(first); remaining.discard(first)
        while remaining:
            last_wits = entity_witnesses[eids_ordered[-1]]
            next_eid = max(remaining, key=lambda eid: len(last_wits & entity_witnesses.get(eid, set())))
            eids_ordered.append(next_eid); remaining.discard(next_eid)
    all_eids = {n["id"] for n in entity_nodes}
    for eid in all_eids - set(eids_ordered):
        eids_ordered.append(eid)

    # Build entity-to-entity adjacency (shared-witness connections)
    ee_adj = defaultdict(lambda: defaultdict(int))
    for e in edges:
        if e.get("dashes"):
            ee_adj[e["from"]][e["to"]] = e["value"]
            ee_adj[e["to"]][e["from"]] = e["value"]

    # Round-table optimization via simulated annealing:
    # minimize total weighted circular distance between connected entities
    def _circ_dist(i, j, n):
        return min(abs(i - j), n - abs(i - j))

    def _order_energy(order, adj):
        n = len(order)
        idx = {eid: i for i, eid in enumerate(order)}
        total = 0
        for eid, neighbors in adj.items():
            i = idx[eid]
            for neighbor, weight in neighbors.items():
                j = idx.get(neighbor)
                if j is not None:
                    total += weight * _circ_dist(i, j, n)
        return total

    if ee_adj:
        initial_energy = _order_energy(eids_ordered, ee_adj)
        best_global_order = list(eids_ordered)
        best_global_energy = initial_energy
        n_ents = len(eids_ordered)

        for restart in range(5):
            order = list(eids_ordered)
            random.shuffle(order)
            cur_energy = _order_energy(order, ee_adj)
            best_energy = cur_energy
            best_order = list(order)
            temp = cur_energy * 0.05
            for _ in range(50000):
                if temp < 1: break
                if random.random() < 0.5:
                    i, j = random.sample(range(n_ents), 2)
                    order[i], order[j] = order[j], order[i]
                else:
                    i, j = sorted(random.sample(range(n_ents), 2))
                    order[i:j] = reversed(order[i:j])
                new_energy = _order_energy(order, ee_adj)
                delta = new_energy - cur_energy
                if delta < 0 or random.random() < math.exp(-delta / temp):
                    cur_energy = new_energy
                    if cur_energy < best_energy:
                        best_energy = cur_energy
                        best_order = list(order)
                else:
                    if random.random() < 0.5:
                        order[i], order[j] = order[j], order[i]
                    else:
                        order[i:j] = reversed(order[i:j])
                temp *= 0.9995
            if best_energy < best_global_energy:
                best_global_energy = best_energy
                best_global_order = best_order

        eids_ordered = best_global_order
        if initial_energy > 0:
            print(f"  Annealing (5 restarts): energy {initial_energy:.0f} -> {best_global_energy:.0f}  ({100 - best_global_energy/initial_energy*100:.1f}% reduction)")

    # Reorder entity_nodes to match
    eid_to_node = {n["id"]: n for n in entity_nodes}
    entity_nodes[:] = [eid_to_node[eid] for eid in eids_ordered if eid in eid_to_node]
    all_nodes = person_nodes + entity_nodes

    # Compute witness reliability: % of named entities corroborated by other witnesses
    for pn in person_nodes:
        pid = pn["id"]
        named_ents = person_entity_counts.get(pid, {})
        total_named = len(named_ents)
        corr_count = 0
        for ev in named_ents:
            eid = entity_map.get(ev)
            if eid is None:
                continue
            other_wits = entity_witnesses.get(eid, set()) - {pid}
            if other_wits:
                corr_count += 1
        pn["corroboratedCount"] = corr_count
        pn["reliability"] = round(corr_count / total_named * 100) if total_named > 0 else 0

    # Mkhwanazi: fixed at center, grey, large
    for n in all_nodes:
        if "Mkhwanazi" in n["label"]:
            n["color"] = {"background": "#777777", "border": "#444444",
                          "highlight": {"background": "#999999", "border": "#444444"}}
            n["size"] = 45
            n["fixed"] = True
            n["x"] = 0
            n["y"] = 0

    # Entities: fixed on an outer circle, largest size
    n_ents = len(entity_nodes)
    ring_radius = 300
    for i, n in enumerate(entity_nodes):
        angle = 2 * math.pi * i / n_ents
        n["x"] = ring_radius * math.cos(angle)
        n["y"] = ring_radius * math.sin(angle)
        n["fixed"] = True
        n["size"] = 50

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

    # Build snippet lookup: (speaker_id, entity_value) -> context text
    print("Building accusation snippets...")
    snippet_rows = conn.execute("""
        SELECT e.speaker_id, e.entity_value, e.context_text, h.day_number
        FROM entities e
        LEFT JOIN hearings h ON h.id = e.hearing_id
        WHERE e.speaker_id IN (SELECT id FROM speakers WHERE role IN ('witness', 'witness_protected'))
          AND e.entity_type IN ({})
        ORDER BY e.speaker_id, e.entity_value
    """.format(ENTITY_TYPES_STR)).fetchall()
    snippet_lookup = {}
    for sr in snippet_rows:
        key = (sr["speaker_id"], sr["entity_value"])
        if key not in snippet_lookup:
            snippet_lookup[key] = (sr["context_text"], sr["day_number"])

    # Query which entities evidence leaders mentioned (for evidence-backed flag)
    el_entities = set(r[0] for r in conn.execute(
        "SELECT DISTINCT e.entity_value FROM entities e "
        "JOIN speakers s ON s.id = e.speaker_id "
        "WHERE s.role = 'evidence_leader' "
        "AND e.entity_type IN ({})".format(ENTITY_TYPES_STR)
    ))

    # Compute accusation strength: mention_count × corroboration × evidence_backing
    person_lookup = {p["id"]: p for p in person_nodes}
    entity_lookup = {e["id"]: e for e in entity_nodes}
    acc_strength = []
    for e in edges:
        if e["from"] > 0 and e["to"] < 0:
            pn = person_lookup.get(e["from"])
            en = entity_lookup.get(e["to"])
            if pn and en:
                corroborators = max(en.get("witnessCount", 1) - 1, 0)
                ev = e.get("entityValue", en["label"])
                evidence_backed = ev in el_entities
                el_weight = 2.0 if evidence_backed else 1.0
                snip, day_num = snippet_lookup.get((pn["id"], ev), ("", None))
                acc_strength.append({
                    "accuser": pn["label"],
                    "entity": ev,
                    "entityType": e.get("entityType", en.get("entityType", "")),
                    "mentions": e["value"],
                    "corroborators": corroborators,
                    "score": round(e["value"] * (1 + corroborators) * el_weight),
                    "source": "evidence_led" if evidence_backed else "witness_only",
                    "evidenceBacked": evidence_backed,
                    "snippet": snip[:250] if snip else "",
                    "day": day_num,
                })
    acc_strength.sort(key=lambda x: x["score"], reverse=True)

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
        "top_mentioned": sorted(
            [{"name": pn["label"], "count": pn.get("mentionedCount", 0)} for pn in person_nodes],
            key=lambda x: x["count"], reverse=True
        )[:5],
        "total_accusations": sum(1 for e in edges if e["from"] > 0 and e["to"] < 0),
        "top_accused": sorted(
            [{"entity": e["label"], "type": e.get("entityType", ""), "accusers": e.get("witnessCount", 0),
              "mentions": e.get("mentionCount", 0)} for e in entity_nodes],
            key=lambda x: x["accusers"], reverse=True
        )[:10],
        "top_accusers": sorted(
            [{"name": p["label"], "entities": p.get("entityCount", 0),
              "segments": p.get("segments", 0), "days": p.get("days", 0)} for p in person_nodes],
            key=lambda x: x["entities"], reverse=True
        )[:10],
        "top_accusations": acc_strength,
        "top_reliable": sorted(
            [{"name": p["label"], "reliability": p.get("reliability", 0),
              "corroborated": p.get("corroboratedCount", 0),
              "total_entities": p.get("entityCount", 0)} for p in person_nodes],
            key=lambda x: x["reliability"], reverse=True
        )[:10],
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

    # ── 8a. Person-to-person edges (typed) ──────────────────────
    print("Building person-to-person edges...")
    person_to_person_edges = []
    p_ids_set = set(person_ids)
    # Edge type 1: questioning — evidence_leader seg immediately before witness seg
    el_ids = set(r["id"] for r in conn.execute(
        "SELECT id FROM speakers WHERE role IN ('evidence_leader', 'commissioner')"
    ))
    questioning_pairs = conn.execute("""
        SELECT a.speaker_id AS from_id, b.speaker_id AS to_id, COUNT(*) AS weight
        FROM transcript_segments a
        JOIN transcript_segments b ON a.id = b.id - 1
                                 AND a.hearing_id = b.hearing_id
        WHERE a.speaker_id IN ({})
          AND b.speaker_id IN ({})
        GROUP BY a.speaker_id, b.speaker_id
        HAVING weight >= 2
    """.format(
        ",".join("?" for _ in el_ids),
        ",".join("?" for _ in p_ids_set),
    ), [*el_ids, *p_ids_set]).fetchall()
    for r in questioning_pairs:
        person_to_person_edges.append({
            "from": r["from_id"],
            "to": r["to_id"],
            "type": "questioning",
            "weight": r["weight"],
        })

    # Edge type 2: co_testified — same hearing day, min 3 shared days
    co_test_pairs = conn.execute("""
        SELECT a.speaker_id AS from_id, b.speaker_id AS to_id,
               COUNT(DISTINCT a.hearing_id) AS shared_days
        FROM transcript_segments a
        JOIN transcript_segments b ON a.hearing_id = b.hearing_id
                                   AND a.speaker_id < b.speaker_id
        WHERE a.speaker_id IN ({})
          AND b.speaker_id IN ({})
        GROUP BY a.speaker_id, b.speaker_id
        HAVING shared_days >= 2
        ORDER BY shared_days DESC
        LIMIT 800
    """.format(
        ",".join("?" for _ in p_ids_set),
        ",".join("?" for _ in p_ids_set)
    ), [*p_ids_set, *p_ids_set]).fetchall()
    for r in co_test_pairs:
        person_to_person_edges.append({
            "from": r["from_id"],
            "to": r["to_id"],
            "type": "co_testified",
            "weight": r["shared_days"],
        })

    # Edge type 3: mentions — any speaker talking about another speaker (by surname match)
    # Build a lookup: surname -> speaker_id for all witnesses
    witness_surname_map = {}
    for pn in person_nodes:
        surname = pn["label"].split()[-1].lower().strip("()")
        if len(surname) > 2:
            witness_surname_map.setdefault(surname, []).append(pn["id"])

    # Get all speaker IDs that have entity data (for source of mentions)
    all_speakers_with_entities = set(r[0] for r in conn.execute(
        "SELECT DISTINCT speaker_id FROM entities"
    ))
    # Query entities where value matches a witness surname
    surname_list = sorted(witness_surname_map.keys(), key=len, reverse=True)
    mention_edges_added = set()
    for r in conn.execute("""
        SELECT e.speaker_id, e.entity_value, e.entity_type, COUNT(*) AS weight
        FROM entities e
        WHERE e.speaker_id IN ({})
          AND e.entity_type IN ({})
        GROUP BY e.speaker_id, e.entity_value
        HAVING weight >= 3
        LIMIT 800
    """.format(ENTITY_TYPES_STR, ",".join("?" for _ in all_speakers_with_entities)),
    [*all_speakers_with_entities]).fetchall():
        val = r["entity_value"].lower().strip()
        for surname, target_ids in witness_surname_map.items():
            if surname in val or val in surname:
                for tid in target_ids:
                    if r["speaker_id"] == tid:
                        continue
                    key = (r["speaker_id"], tid)
                    if key not in mention_edges_added:
                        mention_edges_added.add(key)
                        person_to_person_edges.append({
                            "from": r["speaker_id"],
                            "to": tid,
                            "type": "mentions",
                            "weight": r["weight"],
                        })
                break

    print("Building attention matrix...")
    # Get all evidence leaders (questioners) with segment counts, and witnesses
    questioners = conn.execute("""
        SELECT s.id, s.canonical_name, COUNT(ts.id) AS segments
        FROM speakers s
        JOIN transcript_segments ts ON ts.speaker_id = s.id
        WHERE s.role IN ('evidence_leader', 'commissioner')
        GROUP BY s.id ORDER BY segments DESC
    """).fetchall()
    witnesses_list = conn.execute("""
        SELECT s.id, s.canonical_name, COUNT(ts.id) AS segments
        FROM speakers s
        JOIN transcript_segments ts ON ts.speaker_id = s.id
        WHERE s.role IN ('witness', 'witness_protected')
        GROUP BY s.id ORDER BY segments DESC
        LIMIT 40
    """).fetchall()

    # Build a lookup: (questioner_id, witness_id) -> questioning count
    questioning_counts = {}
    for r in conn.execute("""
        SELECT a.speaker_id AS q_id, b.speaker_id AS w_id, COUNT(*) AS cnt
        FROM transcript_segments a
        JOIN transcript_segments b ON a.id = b.id - 1
                                 AND a.hearing_id = b.hearing_id
        WHERE a.speaker_id IN (SELECT id FROM speakers WHERE role IN ('evidence_leader', 'commissioner'))
          AND b.speaker_id IN (SELECT id FROM speakers WHERE role IN ('witness', 'witness_protected'))
        GROUP BY a.speaker_id, b.speaker_id
        HAVING cnt >= 2
    """).fetchall():
        questioning_counts[(r["q_id"], r["w_id"])] = r["cnt"]

    q_labels = [q["canonical_name"] for q in questioners[:15]]
    w_labels = [w["canonical_name"] for w in witnesses_list]
    q_ids = [q["id"] for q in questioners[:15]]
    w_ids = [w["id"] for w in witnesses_list]

    att_matrix = []
    for qi in q_ids:
        row = []
        for wi in w_ids:
            row.append(questioning_counts.get((qi, wi), 0))
        att_matrix.append(row)

    # Flatten matrix for R compatibility (jsonlite doesn't handle nested lists well)
    flat_data = [item for row in att_matrix for item in row]
    att_nrow = len(att_matrix)
    att_ncol = len(att_matrix[0]) if att_matrix else 0

    # Write attention matrix as separate file (avoids R jsonlite nested-list issues)
    print("Writing attention matrix...")
    att_out = {
        "questioners": q_labels,
        "witnesses": w_labels,
        "data": flat_data,
        "nrow": att_nrow,
        "ncol": att_ncol,
    }
    att_path = OUT_DIR / "attention_matrix.json"
    att_path.write_text(json.dumps(att_out, ensure_ascii=False), encoding="utf-8")
    print(f"  Saved: {att_path}")

    # ── 8c. Speaker entity profiles ─────────────────────────────
    print("Building speaker entity profiles...")
    profile_rows = conn.execute("""
        SELECT e.speaker_id, e.entity_value, e.entity_type, COUNT(*) AS cnt
        FROM entities e
        WHERE e.speaker_id IN (SELECT id FROM speakers WHERE role IN ('witness', 'witness_protected', 'evidence_leader', 'commissioner'))
        GROUP BY e.speaker_id, e.entity_value
        HAVING cnt >= 2
        ORDER BY e.speaker_id, cnt DESC
    """).fetchall()
    speaker_profiles = {}
    for r in profile_rows:
        sid = r["speaker_id"]
        if sid not in speaker_profiles:
            speaker_profiles[sid] = []
        speaker_profiles[sid].append({
            "value": r["entity_value"],
            "type": r["entity_type"],
            "count": r["cnt"],
        })

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
        "person_edges": person_to_person_edges,
        "speaker_profiles": speaker_profiles,
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
