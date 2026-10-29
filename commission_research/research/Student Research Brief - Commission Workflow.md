# Student Research Brief — Commission Investigation Workflow

**Project:** Commission Research Intelligence Dashboard
**Role:** Final-year law student — legal workflow research
**Goal:** Ensure the dashboard's features align with how evidence leaders actually work during commission hearings

---

## 1. Purpose

The Commission Research Intelligence Dashboard is a fully built tool (see `app/` and `pipeline/` directories). The engineering is done. What's missing is **validation that the tool's features match the real-world workflow of the legal team** — specifically evidence leaders examining witnesses during hearings.

This research exists to answer one question:

> **"If an evidence leader had this dashboard open during hearing prep, during examination, and after each hearing day — would it actually help, and if so, how?"**

Your findings will drive the v2 feature roadmap.

---

## 2. Background Context

### What is the Madlanga Commission?

The **Judicial Commission of Inquiry into Criminality, Political Interference and Corruption in the Criminal Justice System** (the Madlanga Commission) is a South African commission of inquiry chaired by Judge Mbuyiseli Madlanga. It investigates:

- Criminality and corruption within the SAPS, NPA, and related agencies
- Political interference in investigations and prosecutions
- The "Big Five" cartel and other organized crime networks

It operates under the **Commissions Act, 1947** and was established by presidential proclamation.

### What the Dashboard Already Does

| Feature | What It Provides |
|---------|-----------------|
| Entity Extraction | 100,000+ entity mentions extracted from all 147+ hearing days — people, orgs, locations, money, case refs, exhibits |
| Full-Text Search | Search every transcript, ruling, statement from one interface with speaker/date filters |
| Network Graph | Visual map of which witnesses named which entities |
| Evidence Compare | Side-by-side view: what commission documents say vs what witnesses say about any entity |
| Story Map | Dual timeline: commission documents vs witness testimony |
| Entity Browser | Browse 16,000+ unique entities by type, see every mention context |
| Contradiction Detection | (Enterprise feature) Flags entities where one witness affirms and another denies, side by side with the wording highlighted |
| Witness Prep Pack | (Professional feature) One-click witness summary: days testified, questioners, entities named |
| Evidence Bundle Export | (Professional feature) Downloadable, printable bundle of every mention of an entity, with citations |
| Citations | Every search result and testimony excerpt carries "Day 47, p.23, lines 10–15"; search results export to CSV |
| Team Notes | Evidence leaders can attach notes to excerpts or flag them as incorrect against the source |

### The Super Dictionary for Prosecutors Vision

The tool aims to be open on every evidence leader's desk as their **default research tool** — like a dictionary but for the entire commission record:

- **Before a hearing:** See everything about tomorrow's witness in 30 seconds
- **During a hearing:** Spot a contradiction → follow up immediately
- **After a hearing:** Generate an evidence bundle → hand to the report team
- **Final report:** Every citation, excerpt, connection one click away

---

## 3. How Commissions of Inquiry Work

### The 5-Phase Lifecycle

| Phase | What Happens | Our Tool's Role |
|-------|-------------|----------------|
| **1. Establishment** | President issues Terms of Reference, appoints chair/judges, rules published, budget allocated | **None — not our scope** |
| **2. Preliminary Investigation** | Legal team gathers initial evidence, calls for submissions, subpoenas documents, identifies witnesses | **None — pre-hearing prep is the legal team's craft, not for a tool to intervene in** |
| **3. Hearings** | Witnesses testify under oath, exhibits entered, transcripts produced, evidence leaders examine and cross-examine | **Primary focus — this is where the dashboard delivers value** |
| **4. Deliberation** | Panel reviews all evidence, drafts findings, considers contradictory evidence, due process to implicated persons | **Supportive — tool provides references and recommendations, not drafting** |
| **5. Report & Referral** | Final report to President, tabled in Parliament, referrals to NPA for prosecution | **Supportive — tool surfaces citations and connections, the legal team drafts** |

### The Hearings Phase (Our Focus) — Daily Workflow

**Morning: Evidence Leader Prepares for the Day**

The evidence leader assigned to examine today's witness reviews:
- The witness's prior statements (if any)
- Previous testimony segments from this witness
- Documents and exhibits they're expected to reference
- Key entities they should be questioned about
- Potential contradictions with other witnesses' testimony

This is currently done by:
- Reading through PDF transcripts manually
- Asking junior researchers to find specific excerpts
- Relying on memory and notes from previous hearing days
- Searching individual PDFs with Ctrl+F

**During the Hearing**

The evidence leader:
- Questions the witness in a structured examination-in-chief
- Presents documents and asks the witness to confirm/explain
- Follows up on answers that raise new questions
- Notes any contradictions with prior testimony
- An entity or name comes up → needs to recall what other witnesses said about it

During this time, juniors and other evidence leaders may:
- Pass notes with references to prior testimony
- Research a name or entity that just came up
- Flag a potential contradiction for follow-up

**After the Hearing**

The team:
- Debriefs on key testimony and findings
- Identifies follow-up witnesses needed
- Compiles evidence references for the record
- Notes entities/patterns that need deeper investigation
- Prepares for the next hearing day's witness

**Cross-Referencing (Ongoing)**

This is the most labour-intensive part:
- "Which witnesses have mentioned Medicare 24?"
- "What did Witness A say about Entity X vs what Witness B said?"
- "Is there documentary evidence supporting this allegation?"
- "When was the first time this entity was named?"

---

## 4. Research Questions

Investigate these with evidence leaders, junior researchers, or anyone who works on commission hearings. Adapt the questions as needed — the goal is real insight, not ticking boxes.

### A. Pre-Hearing Preparation

1. How does an evidence leader currently prepare for a witness examination day? Walk me through the steps.
2. What documents/information do you need to have ready before you start questioning a witness?
3. Where do you currently spend the most time in preparation?
4. If you could have any information about a witness instantly available, what would it be?
5. How do you currently track what a specific witness has said across multiple hearing days?

### B. During-Hearing Support

6. When you're examining a witness and an entity/name comes up, how do you currently check what other witnesses said about it?
7. How often do you spot potential contradictions during a hearing? What happens — do you follow up immediately or make a note?
8. What would make the biggest difference to your effectiveness during an examination?
9. How do junior researchers or co-counsel currently pass you information during a hearing?
10. Is real-time search useful during a hearing, or is it too distracting?

### C. Post-Hearing Analysis

11. After a hearing day, what do you do with the testimony? How is it documented and referenced?
12. How do you currently compile evidence references for the final report?
13. What's the most tedious post-hearing task you'd want automated?

### D. Contradiction Detection

14. How do you currently identify contradictions between witnesses? Walk me through the process.
15. Have there been cases where a contradiction was missed during hearings and only spotted later? What happened?
16. If the tool could automatically flag potential contradictions, how would you want them presented?

### E. Evidence Bundles & Report

17. When you need to compile evidence about a specific entity (e.g., "Medicare 24"), what format do you need it in?
18. What citation format is required for the final report? (e.g., "Day 47, page 23, lines 10-15")
19. Would pre-formatted evidence bundles help, or do you need to write them from scratch each time?

### F. General

20. What's the single biggest information-finding pain point in your current workflow?
21. Have you used any similar tools (legal research databases, document management systems)? What worked, what didn't?
22. Is there any feature you've wished for that doesn't exist?

---

## 5. Methodology

### Suggested Approach

**Step 1: Desk Review (2-3 days)**
- Read the madlanga_downloader.py script to understand what data exists
- Launch the dashboard (`run.ps1` or `launch.bat` from `commission_research/`)
- Explore each of the 13 nav panels to understand current capabilities
- Read the Business Pitch and Value Analysis docs in `business/`

**Step 2: Interview Prep (1 day)**
- Draft a 1-page summary of the tool with screenshots
- Prepare 3-5 scenarios to walk through with interviewees
- Get ethics clearance if required by your faculty

**Step 3: Interviews (5-7 days)**
- Target: 3-5 people with commission experience
- Ideal candidates: current/former evidence leaders, junior researchers, commission legal researchers
- Format: 30-45 minute semi-structured interviews
- Show the tool, ask the research questions, observe reactions

**Step 4: Workflow Mapping (2-3 days)**
- For each workflow step identified in interviews:
  - Map the current process (as-is)
  - Map the ideal process with the tool (to-be)
  - Identify gaps between current tool capabilities and what's needed

**Step 5: Recommendations (2-3 days)**
- Prioritize findings by: pain relief × frequency × feasibility
- Produce a feature priority matrix
- Write up specific recommendations for the v2 prototype

---

## 6. Deliverables

At the end of the research, produce:

### 1. Workflow Diagrams (As-Is vs To-Be)
Visual maps showing:
- Current manual workflow for pre-hearing prep
- Current manual workflow for during-hearing reference
- Current manual workflow for post-hearing analysis
- The same workflows with the dashboard integrated

### 2. Pain Point Heatmap
A simple table ranking each pain point by:
- **Severity** (1-5: how painful is this?)
- **Frequency** (1-5: how often does it occur?)
- **Tool readiness** (1-5: how well does the current tool address this?)

### 3. Feature Priority Matrix
Plot each potential feature on a 2x2 grid:
- **X-axis:** Effort to implement (low → high)
- **Y-axis:** User value (low → high)
- Features in top-right quadrant = do first

### 4. Written Recommendations (2-3 pages)
For each recommendation:
- What the evidence leader needs
- How the tool could address it
- Any specific implementation notes

### 5. Interview Notes (raw)
Include anonymized notes from each interview — verbatim quotes are especially valuable.

---

## 7. Reference Materials

| Resource | Location |
|----------|----------|
| Dashboard Shiny app | `commission_research/app/app.R` |
| Shared logic & data access | `commission_research/app/global.R` |
| Network computation pipeline | `commission_research/pipeline/compute_network.py` |
| Data downloader | `madlanga_downloader.py` |
| Business pitch (for context) | `business/Commission Research Intelligence Dashboard - Business Pitch.md` |
| Value analysis (for cost context) | `business/Value Analysis - Utility vs Current Cost.md` |
| Run the app (batch) | `commission_research/run.bat` |
| Run the app (PowerShell) | `commission_research/run.ps1` |

---

## 8. Key Principles to Keep in Mind

1. **We do NOT want to disrupt the commission process.** The tool should assist, not replace, the expertise of evidence leaders. Every legal and investigative decision stays with the advocates.

2. **The tool is specialized for the Madlanga Commission.** It is purpose-built for this specific context, not a general platform.

3. **The hearings phase is our focus.** Pre-hearing establishment and preliminary investigation are out of scope.

4. **For report drafting, the tool provides recommendations and citations only.** The legal team writes the actual report.

5. **Contradiction detection, witness prep packs, evidence bundles, citations and team notes are built as first versions.** Test them against real workflows: your findings decide how they change in v2. Question 18 (citation format) matters most, since the tool now assumes "Day, page, lines".

---

*This research brief was prepared July 2026. The findings will directly inform the v2 prototype and the sales/outreach strategy.*

<!-- test update -->

