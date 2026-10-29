# Prototype Roadmap — Commission Research Intelligence Dashboard

**Living document.** Updated as features are built, tested, or planned.

---

## Feature Inventory

| Feature | Status | Notes |
|---------|--------|-------|
| | | |
| **Data Pipeline** | | |
| Transcript download (Supabase API) | ✅ Complete | `madlanga_downloader.py` — fetches all hearings, media, documents |
| Transcript parsing (.txt → segments) | ✅ Complete | `parse_transcripts.py` — speaker-tagged segments with page and line-on-page for citations |
| Statement parsing (PDFs → text) | ✅ Complete | `parse_statements.py` |
| Speaker normalization | ✅ Complete | `normalize_speakers.py` — raw labels → canonical names + roles |
| Entity extraction (regex + gazetteers) | ✅ Complete | `extract_entities.py` — 100k+ entity mentions, 16k+ unique |
| FTS5 search index | ✅ Complete | `index_search.py` — SQLite full-text search |
| Network computation (bipartite graph) | ✅ Complete | `compute_network.py` — person→entity edges with accusation scoring |
| Story map construction | ✅ Complete | `build_story_map.py` — dual timeline (documents + testimony) |
| Institutional analysis DB | ✅ Complete | `build_institutional_db.py` — now a `build_db.py` step (`institutions`) |
| | | |
| **Dashboard** | | |
| Overview — stat cards + mini network | ✅ Complete | Top 40 persons + 40 entities, concentric layout (static) |
| Connections — full network graph | ✅ Complete | Filterable by connection type, concentric layout (static) |
| Witnesses & Entities — role-based cards | ✅ Complete | Speaker profiles with entity mentions |
| Attention Map — questioning heatmap | ✅ Complete | Who questioned whom, intensity matrix. Fixed: had stopped rendering after the `parse_json` change |
| Timeline — hearing chronology | ✅ Complete | Interactive plot + table of all hearing days |
| Search — FTS5 full-text | ✅ Complete | Keyword/phrase/wildcard/boolean, speaker + date filters. Fixed: "From" date defaulted to today and hid all earlier results |
| Entities — entity browser | ✅ Complete | 16k+ entities browsable by type, context snippets |
| Story Map — parallel timelines | ✅ Complete | Docs vs testimony, entity + witness filters |
| Evidence Compare — side-by-side | ✅ Complete | What documents say vs what witnesses say about any entity |
| Contradictions — flagged conflicts | ✅ Complete | Affirm vs deny detection across witnesses, side-by-side view with highlighted wording, type filter |
| Institutions — institutional analysis | ✅ Complete | Leadership, AGSA audits, allegations, conflicts of interest, research gaps per institution |
| Notes — shared annotations | ✅ Complete | Team notes and "flag as incorrect" on search results and testimony; Notes tab with CSV export |
| Dashboard — stats page | ✅ Complete | Summary cards, top accused, evidence corroboration, validity breakdown |
| | | |
| **Concentric Network Layout** | ✅ Complete | Witnesses on inner circle, entities on outer circle, barycenter ordering. Nodes are draggable; "Live physics" switch on Overview and Connections. |
| | | |
| **Planned / In Progress** | | |
| Evidence Bundle Export | ✅ Complete | Downloads to the browser (works on shinyapps.io); printable HTML with Print / Save as PDF and citations |
| Witness Preparation Pack | ✅ Complete | One-click witness summary (Professional tier) |
| Contradiction Engine (dedicated view) | ✅ Complete | See Contradictions above (Enterprise tier). Keyword-based stance, so flags are leads to verify |
| Multi-user annotations | ✅ Complete | Shared SQLite store; needs persistent storage (`MADLANGA_ANNOTATIONS_DB`) on hosts that wipe the disk |
| Citation export with line references | ✅ Complete | "Day 47, p.23, lines 10–15" in Search, Evidence Compare, Contradictions and bundles; CSV export from Search. Requires a pipeline rebuild |
| License enforcement | ✅ Complete | On by default; invalid/expired/revoked licenses block access; renewal tool now signs the tier |
| Automated tests | ✅ Complete | `tests/python` (pytest) and `tests/r` (testthat), run in GitHub Actions |
| Student research feedback integration | 🔲 Waiting | Brief updated to reflect what is built; findings not yet received |

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
| 2026-10-29 | Evidence Bundle download, citation export, contradiction detection, Institutions and Notes tabs, license enforcement, network dragging/physics, tests |
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
