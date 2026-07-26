# Prototype Roadmap — Commission Research Intelligence Dashboard

**Living document.** Updated as features are built, tested, or planned.

---

## Feature Inventory

| Feature | Status | Notes |
|---------|--------|-------|
| | | |
| **Data Pipeline** | | |
| Transcript download (Supabase API) | ✅ Complete | `madlanga_downloader.py` — fetches all hearings, media, documents |
| Transcript parsing (.txt → segments) | ✅ Complete | `parse_transcripts.py` — speaker-tagged segments |
| Statement parsing (PDFs → text) | ✅ Complete | `parse_statements.py` |
| Speaker normalization | ✅ Complete | `normalize_speakers.py` — raw labels → canonical names + roles |
| Entity extraction (regex + gazetteers) | ✅ Complete | `extract_entities.py` — 100k+ entity mentions, 16k+ unique |
| FTS5 search index | ✅ Complete | `index_search.py` — SQLite full-text search |
| Network computation (bipartite graph) | ✅ Complete | `compute_network.py` — person→entity edges with accusation scoring |
| Story map construction | ✅ Complete | `build_story_map.py` — dual timeline (documents + testimony) |
| | | |
| **Dashboard** | | |
| Overview — stat cards + mini network | ✅ Complete | Top 40 persons + 40 entities, concentric layout (static) |
| Connections — full network graph | ✅ Complete | Filterable by connection type, concentric layout (static) |
| Witnesses & Entities — role-based cards | ✅ Complete | Speaker profiles with entity mentions |
| Attention Map — questioning heatmap | ✅ Complete | Who questioned whom, intensity matrix |
| Timeline — hearing chronology | ✅ Complete | Interactive plot + table of all hearing days |
| Search — FTS5 full-text | ✅ Complete | Keyword/phrase/wildcard/boolean, speaker + date filters |
| Entities — entity browser | ✅ Complete | 16k+ entities browsable by type, context snippets |
| Story Map — parallel timelines | ✅ Complete | Docs vs testimony, entity + witness filters |
| Evidence Compare — side-by-side | ✅ Complete | What documents say vs what witnesses say about any entity |
| Contradictions — flagged conflicts | ✅ Complete | Entities mentioned by multiple witnesses |
| Dashboard — stats page | ✅ Complete | Summary cards, top accused, evidence corroboration, validity breakdown |
| | | |
| **Concentric Network Layout** | ✅ Complete | Witnesses on inner circle, entities on outer circle, barycenter ordering. TODO: re-enable physics for drag interaction. |
| | | |
| **Planned / In Progress** | | |
| Evidence Bundle Export | ⚠️ Partial | All data exists — needs UI to format as printable HTML/PDF |
| Witness Preparation Pack | 🔲 Planned | One-click witness summary card |
| Contradiction Engine (dedicated view) | 🔲 Planned | Auto-flag conflicting testimony across witnesses |
| Multi-user annotations | 🔲 Planned | Shared notes on excerpts |
| Citation export with line references | 🔲 Planned | "Day 47, p.23, lines 10-15" format |
| Student research feedback integration | 🔲 Planned | Incorporate findings from law student research brief |

---

## Status Legend

| Icon | Meaning |
|------|---------|
| ✅ Complete | Built, loaded with real data, tested, deployable |
| ⚠️ Partial | Functional but needs polish before client demo |
| 🔲 Planned | Designed but not yet implemented |

---

## Recent Changes

| Date | Change |
|------|--------|
| 2026-07-25 | Concentric layout applied to Overview and Connections networks |
| 2026-07-25 | Network graphs set to static mode. TODO in code to re-enable physics. |
| 2026-07-25 | Value Analysis rewritten — new time-recovery framing + delay cost data |
| 2026-07-25 | Student Research Brief created for law student workflow research |
| 2026-07-25 | Investigative Story Package — 3 worked examples for journalists |
| 2026-07-25 | Auto-PDF watcher (`tools/md_to_pdf_watcher.py`) — professional styling via pandoc + wkhtmltopdf |

---

## Notes

- The tool is **purpose-built for the Madlanga Commission** — not a generic platform
- All pipeline scripts are in `commission_research/pipeline/`
- All dashboard code is in `commission_research/app/`
- Features listed as "planned" should be informed by the Student Research Brief findings
- The student research brief at `research/Student Research Brief - Commission Workflow.md` outlines what needs investigation
