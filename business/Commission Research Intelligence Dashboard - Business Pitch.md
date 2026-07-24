# Commission Research Intelligence Dashboard

**A Legal Research & Analysis Tool for the Madlanga Commission of Inquiry**

---

## 1. Executive Summary

The Commission Research Intelligence Dashboard is an operational research tool purpose-built for the Madlanga Commission's legal team. It ingests, structures, and cross-references the entire public record of the commission — 147+ hearing days, thousands of transcript pages, rulings, statements, and documents — and surfaces connections between witnesses, entities, and evidence in seconds.

Its core purpose is to improve the **quality** of the investigation. By making every connection between witnesses, entities, and evidence instantly visible, the dashboard ensures that evidence leaders build a more complete, more coherent evidentiary record — fewer missed connections, stronger cross-examinations, and a final report that rests on every relevant piece of testimony, not just what the team can remember or manually find.

**This is not a replacement tool.** It does not reduce headcount, replace any evidence leader, or automate any judgment call. Every finding, every question, every legal conclusion still comes from the advocates. The dashboard simply eliminates the manual labour of finding, cross-referencing, and recalling information — giving each team member the equivalent of a research assistant with perfect memory of every word spoken across 147 hearing days. It makes a good team extraordinary by removing the administrative friction that slows them down.

The tool is already built, tested, and populated with all commission data to date. It requires no development lead time, no IT procurement, and no integration with government systems. It is ready to deploy immediately.

---

## 2. The Problem

The Madlanga Commission's evidence leaders and legal researchers currently work with:

- **Raw PDF transcripts** — 147+ separate documents, each hundreds of pages long
- **Manual cross-referencing** — finding which witnesses mentioned which entities requires re-reading or keyword-searching individual PDFs
- **Scattered document repositories** — rulings, statements, applications, and exhibits stored across different systems
- **No entity tracking** — no way to instantly see all mentions of "Cat Matlala," "Medicare 24," "Feroz Khan," or "the Big Five cartel" across the entire record
- **No network analysis** — the connections between witnesses and the entities they name exist only in the heads of the evidence leaders

This means legal researchers spend hours doing what a computer can do in milliseconds. At daily rates of R20,000–R64,000 for senior counsel and R7,000–R47,000 for juniors, every hour saved translates directly to budget preserved.

#### D. Evidence preparation delays

Evidence leaders prepare bundles of documents to take witnesses through — prior statements, emails, WhatsApp messages, bank records. Finding the right excerpt from months of testimony to confront a witness with their own prior contradictory statement is a manual, time-consuming process. When evidence is handed to witnesses late or key documents are missed, it wastes hearing time, frustrates the panel, and weakens the evidentiary record. The dashboard eliminates this by giving the legal team instant access to every statement any witness has made about any entity, organized by date and cross-referenced across the full record.

---

## 3. Our Solution

The Commission Research Intelligence Dashboard is a comprehensive investigative research tool that transforms unstructured public records into an interconnected, searchable intelligence platform. Its design philosophy centers on two principles: **investigative quality** (no connection goes unseen) and **efficiency** (every search, cross-reference, and comparison happens in seconds, not hours).

### Core Capabilities

#### A. Entity Extraction & Cross-Referencing

Every transcript, statement, and document is automatically processed to extract named entities: people, organizations, locations, money amounts, case references, dates, and exhibits. Each extraction preserves the surrounding context so you can see exactly what was said.

- **147+ hearing days** — all transcripts parsed and entity-tagged
- **100,000+ entity mentions** — extracted and linked to their source
- **Instant recall** — type an entity name and see every mention across the entire record

#### B. Network Graph — Visualizing Connections

The interactive network graph maps every witness against every entity they named. Bigger nodes = more mentions. Darker nodes = more central to the record. Click any node to see what entities a witness named, or which witnesses named a specific entity.

- **Overview mode** — see the top 80 most-connected people and entities at a glance
- **Full network mode** — explore all connections with filtering by role and connection count
- **Edge details** — click a connection line to see the actual testimony excerpt

#### C. Full-Text Search Across the Entire Record

Search every transcript, ruling, statement, and document from a single interface. Supports keywords, exact phrases, wildcards, and boolean operators. Filter by date range and speaker.

- **Unified index** — all text sources in one searchable database
- **Rich snippets** — results show surrounding context with highlights
- **Speaker filtering** — narrow results to specific witnesses or evidence leaders

#### D. Timeline — Hearing History at a Glance

See every hearing day plotted on an interactive timeline. Click any day to see the summary. Track the commission's progress from Day 1 to Day 147+.

#### E. Entity Browser

Browse all extracted entities (16,000+ unique values) by type: organizations, people, locations, case references, money amounts, exhibits, and vehicles. Select any entity to see every context it appears in across the entire record.

#### F. Story Map — Parallel Timelines

Two synchronized timelines — commission documents on one side, witness testimony on the other — filtered by entity, witness, and date range. See what the commission was publishing while witnesses were testifying. Highlight cross-references to spot contradictions and corroborations.

#### G. Evidence Compare

Select any entity (person, organization, location) and see in parallel:

- **What the commission's documents say** about that entity
- **What the witnesses say** about that entity

This is the core investigative function — finding gaps, contradictions, and corroborations between the official record and live testimony. It directly improves the quality of the investigation by ensuring evidence leaders have a complete picture before they put a question to a witness.

## How It Fits Into the Daily Workflow

The dashboard does not require anyone to change how they work. It plugs into existing workflows at specific points where manual effort is highest:

### Before a Hearing (Evidence Preparation — 30 min → 2 min)

**Current workflow:** An evidence leader is preparing to examine a witness tomorrow. They need to find every prior statement this witness made, every entity they named, and any contradictions with commission documents. A junior researcher spends 2–4 hours searching through PDFs, or the evidence leader relies on memory.

**With the dashboard:** Open the dashboard. Type the witness name in Search. Every segment of their testimony appears instantly, organized by date. Open Evidence Compare and select the key entities — the dashboard shows what the witness said vs what commission documents say, side by side. Total time: 2 minutes.

### During a Hearing (Real-Time Reference — 10 min → 30 seconds)

**Current workflow:** A witness says something that contradicts a prior witness from 3 months ago. The evidence leader makes a mental note, but the moment passes — finding the exact excerpt during a live hearing is impractical.

**With the dashboard:** Type the entity or topic into Search while the witness is speaking. The dashboard shows every mention across the entire record with context. The evidence leader can follow up immediately, strengthening the cross-examination in real time.

### After a Hearing (Cross-Referencing & Report Prep — 4 hours → 5 minutes)

**Current workflow:** After a hearing day, a junior researcher is asked to compile all references to a specific entity (e.g., "Medicare 24" or "Feroz Khan") across the full record — every document mention and every witness mention. This takes hours of manual searching.

**With the dashboard:** Open the Entity Browser. Select the entity. The dashboard shows every mention across all 147 days — who said it, when, and the exact context. Export for use in the final report. Time: 5 minutes.

### Building the Final Report

The dashboard's ability to instantly surface every reference to any entity across the full record means the team can write a report that rests on every relevant piece of testimony — not just what they can remember or manually find. The parallel Evidence Compare view ensures the report accurately reflects both the documentary record and the live testimony, side by side.

In all of these cases, the dashboard **does not make a single legal or investigative decision.** Every question, every conclusion, every recommendation remains with the evidence leaders. The dashboard simply removes the friction of finding information — giving the team more time to think, question, and build a stronger case.

### Technical Architecture

- **Language**: R/Shiny (fully portable)
- **Data storage**: SQLite (single file, no server needed)
- **NLP pipeline**: Python-based entity extraction using commission-optimized rules
- **Deployment**: Runs on any Windows or Linux machine. No internet required after initial data load.
- **Security**: All data is already public. No classified or confidential material is ingested.

---

## 4. Cost Justification

### What the Commission Currently Spends

| Cost Center | Rate | Daily Cost (full team) |
|---|---|---|
| Chief Evidence Leader (Chaskalson SC) | R64,000/day | R64,000 |
| Senior Evidence Leaders (Sello SC, Hassim SC) | R40,000–R60,000/day each | R120,000–R180,000 |
| Junior evidence leaders & researchers | R7,000–R47,000/day | R28,000–R188,000 |
| **Total legal team daily cost** | | **R212,000 – R432,000/day** |

Every hour saved per person per day = **R26,500 – R54,000/day in recovered research time**.

### The Real Cost: Investigative Quality

The commission's mandate is to produce a definitive account of criminal infiltration of the justice system. Every connection missed, every contradiction unnoticed, every corroboration left unfound weakens that account. The dashboard ensures the investigation is as thorough as the record allows — not as thorough as the team's manual capacity permits.

### What the Dashboard Eliminates or Reduces

| Activity | Manual Time | With Dashboard | Saving per Day |
|---|---|---|---|
| Finding all mentions of an entity across 147 days | 2–4 hours | 10 seconds | R5,000–R20,000 |
| Cross-referencing witness statements against documents | 3–6 hours | 2 minutes | R7,500–R30,000 |
| Building a witness-entity connection map | 8–16 hours (one-off) | Built automatically | R40,000–R80,000 (one-off) |
| Searching transcripts for keywords/themes | 1–2 hours per search | Instant | R2,500–R10,000 per search |
| Preparing evidence comparison summaries | 4–8 hours per entity | Instant export | R10,000–R40,000 per entity |
| Finding a prior contradictory statement by a witness | 1–3 hours searching transcripts | 10 seconds | R2,500–R15,000 per search |
| Compiling evidence bundles for witness preparation | 4–8 hours per witness | Built automatically | R10,000–R40,000 per witness |

### The Real Cost the Dashboard Reduces: Delayed or Missed Connections

The biggest cost is not billable hours. It is the investigative connections that are missed because a junior researcher did not spot that Witness A and Witness B both named the same entity three months apart. The dashboard surfaces these connections automatically. The Zondo Commission demonstrated that commissions that catch connections early produce stronger referrals — and stronger referrals lead to convictions and asset recoveries. The R875 million recovered from McKinsey alone dwarfs any research tool cost.

---

## 5. Pricing & Engagement Model

> **NOTE TO SELF (not for client):** These are internal pricing notes. The pitch to the commission should focus on value delivered and budget fit. Pricing is discussed after demo.

### Pricing Notes

The R100.7m "goods & services" budget line is the target. Within that, the sub-line for **consultants** and **legal services** is where this fits.

The commission has already spent R123m of R147m as of April 2026, and additional funding has been requested for the extension to November 2026. The timing is favorable — they need tools to accelerate the remaining work.

### Proposed Engagement Options

**Option A: Fixed-Price Deliverable**
- The complete dashboard, deployed and configured with all data
- 1-day training session for the legal team
- Documentation and handover
- Price range: R250,000 – R500,000
- Invoice under "consulting services" or "legal research support"

**Option B: Monthly Retainer (for the extension period, Aug–Nov 2026)**
- Dashboard deployment + weekly data updates as new hearings are published
- On-call support for evidence leaders
- Custom entity/query development on request
- Price range: R40,000 – R80,000/month

**Option C: Daily Rate (if embedded with the legal team)**
- On-site or remote as a research analyst / data specialist
- Price range: R15,000 – R30,000/day

### Pricing Justification Notes (for negotiations)

**Comparison points:**
- A single evidence leader at R40,000–R64,000/day costs more in 4–5 days than the entire dashboard
- The dashboard does work equivalent to 2–3 junior researchers full-time
- The tool is already built — no development risk for the commission
- Data pipeline is automated — new hearing days are ingested as they publish

**Walk-away point:** R150,000 minimum for deployment. Below that, the value of the time spent negotiating exceeds the contract value.

**Upsells after initial engagement:**
- Ongoing data updates through November 2026
- Custom network analysis reports for specific case files
- Integration with the commission's final report drafting

---

## 6. Target Contacts & Approach Strategy

### Primary Targets

| Contact | Role | Approach |
|---|---|---|
| **Adv. Matthew Chaskalson SC** | Chief Evidence Leader | **Direct email**: [contact via commission]. Pitch the tool as a force multiplier for his team. He is the decision-maker for legal team tools. |
| **Dr Nolitha Vukuza** | Commission Secretary | Controls the budget. Reach via enquiries@criminaljusticecommission.org.za. Ask to be directed to her office. |

### Secondary Targets

| Contact | Role | Approach |
|---|---|---|
| **Adv. Mahlape Sello SC** | Evidence Leader | Can endorse the tool to Chaskalson. Reach via the commission or through Chaskalson. |
| **Adv. Adila Hassim SC** | Evidence Leader | High-profile, may influence budget decisions. Reach via Thulamela Chambers ([contact via commission]). |
| **Jeremy Michaels** | Spokesperson | Good entry point. Can direct your proposal to the right person. |

### Email Pitch Strategy

**First email to Chaskalson:** Brief, direct, focused on value.
- Reference the State Capture Commission (he led money-flows workstream there — understands value of structured data)
- Mention that the dashboard already has all 147+ days of public data ingested
- Offer a 30-minute demo
- No pricing in the first email

**Second contact (if no response in 5 days):** Call Victoria Mxenge Group at [contact via commission] and ask to speak to his clerk.

**Fallback:** Submit via the commission's general enquiries email with subject line: "Proposal: Research Intelligence Tool for the Legal Team — Attention Dr Vukuza"

---

## 7. Next Steps

1. **Demo preparation** — Prepare a live walkthrough of the dashboard showing specific examples relevant to current hearings (e.g., Andrea Johnson testimony Days 144–146, or the Khumalo/Mokwele case)
2. **First contact** — Email Adv. Chaskalson SC
3. **Demo meeting** — 30-minute screen share showing the tool with commission data
4. **Budget alignment** — After demo, discuss budget fit under "consulting services / legal research support"
5. **Deployment** — 24-hour turnaround. The tool runs immediately on any Windows machine.

---

*Prepared for internal planning purposes. Pricing and strategy notes are confidential to the project owner.*
