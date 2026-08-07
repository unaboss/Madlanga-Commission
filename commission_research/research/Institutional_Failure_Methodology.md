# Institutional Failure Analysis — Methodology

## Why We're Collecting This Data

The Madlanga Commission is investigating individual crimes and corruption. Our argument is that these are symptoms of **systematically failed institutions**. Arresting individuals won't fix broken institutions. We're collecting data to prove the structural pattern.

The commission is producing testimony **right now** (hearings ongoing). Live evidence + public audit records + leadership timelines = a coherent institutional failure narrative.

---

## How We're Doing It

### Step 1: Per-Institution Research
For each target institution, compile:

| Data Point | Source |
|---|---|
| Leadership positions list | Annual reports, gov gazettes, PMG |
| Person name per position per year | Same |
| Tenure dates (start, end) | Same |
| AGSA audit outcome per financial year | AGSA reports |
| Material irregularities found | AGSA reports |
| Irregular expenditure totals | AGSA reports |
| Parliamentary oversight findings | PMG committee minutes |

### Step 2: Per-Person Career Timeline
For each person identified in Step 1:

- Every institution they've worked at
- Role held at each institution
- Tenure dates
- Cross-institutional flags (same person at multiple target institutions)

### Step 3: Map Witnesses into the Structure
For each commission witness:

- Determine their rank AND institution at the time of the incidents they describe (may differ from their testifying rank)
- Place them in the year-by-year chain of command

### Step 4: Trace Allegations Upward
For each allegation/crime a witness describes:

- "Witness X (rank Y in year Z) said [specific allegation]"
- Who was their commanding officer in year Z?
- Did that officer testify? What did they say?
- Repeat up the chain: rank → commanding officer → next rank → next commanding officer → top

---

## The Data Structure (Year-Keyed)

Every data point is tied to a **financial year** (April–March) because:
- AGSA audit outcomes are annual
- Leadership changes happen by year
- Commission incidents span 2020–2026
- A witness's rank at time of incident ≠ their rank at time of testifying

```
Institution
  └── Financial Year (2020/21, 2021/22, ... 2025/26)
       ├── Leadership
       │    ├── Accounting Officer: [Name]
       │    ├── CFO: [Name]
       │    ├── HODs: [Name], [Name], ...
       │    └── ...
       ├── AGSA Audit
       │    ├── Outcome: (Clean / Qualified / Adverse / Disclaimer)
       │    ├── Irregular Expenditure: R[amount]
       │    └── Material Findings: [list]
       ├── Parliamentary Oversight
       │    └── Key issues raised: [list]
       ├── Commission Witnesses (at their rank IN THAT YEAR)
       │    └── [Name] → What they said about this institution in this period
       └── Allegations Mapped Upward
            └── Allegation → Person named → Their commanding officer that year → Next level → Top
```

---

## Target Institutions (in priority order)

| # | Institution | Type | Why |
|---|---|---|---|
| 1 | **IDAC** (NPA) | Anti-corruption unit | Head resigned day of testifying — live lead |
| 2 | **NPA** | Prosecuting authority | IDAC's parent, Shamila Batohi is NDPP |
| 3 | **SAPS** | National police | "The web" — most witnesses, largest budget, links to everything |
| 4 | **City of Ekurhuleni** | Municipality | Mashazi connection, EMPD sits here, SCOPA engaged |
| 5 | **EMPD** | Metro police | Under Ekurhuleni, governed by SAPS Act |
| 6 | **IPID** | Police oversight | Investigates SAPS misconduct |
| 7 | **DPCI / HAWKS** | Priority crimes | Within SAPS, investigates serious crime |
| 8 | **SSA** | State security | Shadow budgets, intelligence |
| 9 | **SIU** | Special investigations | Proclamations, forensic audits |
| 10 | **TMPD** | Metro police (Tshwane) | Similar structure to EMPD |

---

## Research Sources

| Source | What It Provides |
|---|---|
| **AGSA** (Auditor-General SA) | Annual audit outcomes per institution, material irregularities, financial misconduct findings |
| **PMG** (Parliamentary Monitoring Group) | Committee minutes, portfolio committee oversight, SCOPA hearings |
| **Government Gazettes** | Official appointments, terminations, suspensions |
| **Annual Reports** | Org structure, leadership names, budget, performance |
| **Commission Transcripts** | Witness testimony, specific allegations, institutional references |
| **News Archives** | Resignations, scandals, context |
