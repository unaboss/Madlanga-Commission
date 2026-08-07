"""
build_db.py — Build institutional_analysis.db with full schema and seed data.
"""
import sqlite3
from pathlib import Path

PIPELINE_DIR = Path(__file__).resolve().parent
DB_PATH = PIPELINE_DIR.parent / "data" / "institutional_analysis.db"
if DB_PATH.exists():
    DB_PATH.unlink()

conn = sqlite3.connect(str(DB_PATH))
conn.execute("PRAGMA foreign_keys = ON")
conn.execute("PRAGMA journal_mode = WAL")
c = conn.cursor()

# ── Schema ──────────────────────────────────────────
c.executescript("""
CREATE TABLE institutions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    department TEXT NOT NULL,
    abbreviation TEXT NOT NULL,
    jurisdiction TEXT NOT NULL,
    parent_id INTEGER REFERENCES institutions(id),
    governing_institution_id INTEGER REFERENCES institutions(id),
    budget REAL,
    notes TEXT
);

CREATE TABLE people (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    title TEXT,
    commission_witness INTEGER DEFAULT 0,
    speaker_id INTEGER,
    has_budget_authority_ever INTEGER DEFAULT 0,
    notes TEXT
);

CREATE TABLE positions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL REFERENCES people(id),
    institution_id INTEGER NOT NULL REFERENCES institutions(id),
    title TEXT NOT NULL,
    is_accounting_officer INTEGER DEFAULT 0,
    is_cfo INTEGER DEFAULT 0,
    start_date TEXT,
    end_date TEXT,
    budget_authority INTEGER DEFAULT 0,
    budget_authority_type TEXT,
    appointed_by TEXT,
    appointed_by_person_id INTEGER REFERENCES people(id),
    source TEXT,
    notes TEXT
);

CREATE TABLE allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    institution_id INTEGER NOT NULL REFERENCES institutions(id),
    financial_year TEXT NOT NULL,
    source_of_funds TEXT,
    purpose TEXT,
    amount_allocated REAL,
    amount_spent REAL,
    amount_unspent REAL,
    task_completed INTEGER,
    source_document TEXT
);

CREATE TABLE allocation_authorizers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    allocation_id INTEGER NOT NULL REFERENCES allocations(id),
    person_id INTEGER NOT NULL REFERENCES people(id),
    role TEXT,
    date_authorized TEXT,
    notes TEXT
);

CREATE TABLE audit_outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    institution_id INTEGER NOT NULL REFERENCES institutions(id),
    financial_year TEXT NOT NULL,
    audit_opinion TEXT CHECK(audit_opinion IN ('unqualified_clean','unqualified_findings','qualified','adverse','disclaimer','not_audited')),
    has_findings INTEGER DEFAULT 0,
    material_irregularities TEXT,
    irregular_expenditure_details TEXT,
    supply_chain_findings INTEGER DEFAULT 0,
    source TEXT
);

CREATE TABLE witness_topics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    witness_id INTEGER NOT NULL REFERENCES people(id),
    institution_id INTEGER NOT NULL REFERENCES institutions(id),
    day_numbers TEXT,
    key_topics TEXT,
    sentiment TEXT
);

CREATE TABLE allegations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    witness_id INTEGER NOT NULL REFERENCES people(id),
    target_institution_id INTEGER REFERENCES institutions(id),
    target_person_id INTEGER REFERENCES people(id),
    category TEXT,
    severity TEXT CHECK(severity IN ('critical','high','medium','low')),
    summary TEXT NOT NULL,
    day_number INTEGER,
    context_snippet TEXT,
    corroborated_by TEXT
);

CREATE TABLE cross_institutional_moves (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL REFERENCES people(id),
    from_institution_id INTEGER NOT NULL REFERENCES institutions(id),
    to_institution_id INTEGER NOT NULL REFERENCES institutions(id),
    from_role TEXT NOT NULL,
    to_role TEXT NOT NULL,
    move_date TEXT,
    pattern_type TEXT,
    source TEXT
);

CREATE TABLE conflicts_of_interest (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    institution_primary_id INTEGER REFERENCES institutions(id),
    institution_secondary_id INTEGER REFERENCES institutions(id),
    category TEXT CHECK(category IN ('structural','financial','personnel','political')),
    severity TEXT CHECK(severity IN ('critical','high','medium','low')),
    source TEXT,
    detail TEXT,
    commission_mention INTEGER DEFAULT 0
);

CREATE TABLE conspirator_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_a_id INTEGER NOT NULL REFERENCES people(id),
    person_b_id INTEGER NOT NULL REFERENCES people(id),
    institution_id INTEGER REFERENCES institutions(id),
    evidence TEXT
);

CREATE TABLE sources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ref_table TEXT,
    ref_id INTEGER,
    source_type TEXT CHECK(source_type IN ('pmg','agsa','news','transcript','website','gov_gazette','annual_report')),
    url TEXT,
    date_accessed TEXT,
    reliability TEXT CHECK(reliability IN ('confirmed','inferred','unverified'))
);
""")

# ── Seed: Institutions ──────────────────────────────
c.executemany("INSERT INTO institutions (department, abbreviation, jurisdiction, parent_id, governing_institution_id, budget, notes) VALUES (?,?,?,?,?,?,?)", [
    ("Department of Police", "Police Ministry", "national", None, None, None, "Political oversight of SAPS. Minister Senzo Mchunu."),
    ("South African Police Service", "SAPS", "national", 1, 1, 120900000000, "National police service. Largest department by budget."),
    ("Crime Intelligence Division", "Crime Intelligence", "unit", 2, 2, None, "Division within SAPS. CFO Solly Lazarus investigated by IDAC."),
    ("Directorate for Priority Crime Investigation", "DPCI/HAWKS", "unit", 2, 2, None, "Priority crimes unit within SAPS."),
    ("Forensic Science Laboratory", "FSL", "unit", 2, 2, None, "SAPS forensic lab. Resource constraints flagged in audit."),
    ("National Prosecuting Authority", "NPA", "national", None, None, 5583000000, "Independent prosecuting authority. Reports to Minister of Justice."),
    ("Investigating Directorate Against Corruption", "IDAC", "unit", 6, 6, 260000000, "Anti-corruption unit within NPA. Head resigned Jul 2026."),
    ("Asset Forfeiture Unit", "AFU", "unit", 6, 6, None, "Unit within NPA handling asset recovery."),
    ("Specialised Commercial Crime Unit", "SCCU", "unit", 6, 6, None, "Commercial crime prosecution unit within NPA."),
    ("City of Ekurhuleni", "Ekurhuleni", "metro", None, None, None, "Gauteng metro. SCOPA engagement Jun 2026."),
    ("Ekurhuleni Metropolitan Police Department", "EMPD", "unit", 10, 2, None, "Metro police. Governed by SAPS Act but under municipality."),
    ("Independent Police Investigative Directorate", "IPID", "national", None, None, None, "Oversees SAPS misconduct investigations."),
    ("State Security Agency", "SSA", "national", None, None, None, "Intelligence service. Secondments to IDAC."),
    ("Special Investigating Unit", "SIU", "national", None, None, None, "Special investigations by proclamation."),
    ("Tshwane Metropolitan Police Department", "TMPD", "unit", None, None, None, "Metro police for City of Tshwane."),
    ("National Treasury", "Treasury", "national", None, None, None, "Controls national budget, PFMA compliance."),
    ("Department of Cooperative Governance", "COGTA", "national", None, None, None, "Oversees municipalities including Ekurhuleni."),
])

# Build a mapping for quick reference
inst_map = {}
for r in c.execute("SELECT id, abbreviation FROM institutions").fetchall():
    inst_map[r[1]] = r[0]

# ── Seed: People ───────────────────────────────────
c.executemany("INSERT INTO people (full_name, title, commission_witness, speaker_id, has_budget_authority_ever, notes) VALUES (?,?,?,?,?,?)", [
    ("Dr Imogen Mashazi", "Dr", 1, 94, 1, "City Manager Ekurhuleni. Accounting Officer. Retired Jul 2025."),
    ("Adv Andrea Johnson", "Adv", 1, None, 1, "Head of IDAC. Resigned 26 Jul 2026 day of testifying."),
    ("Colonel Padayachee", "Col", 1, None, 0, "IDAC investigating officer. Testified Days 139-141."),
    ("Lt Gen Nhlanhla Mkhwanazi", "Lt Gen", 1, 4, 1, "National Commissioner SAPS. Central figure at commission."),
    ("Gen Fannie Masemola", "Gen", 1, 13, 1, "Former National Commissioner SAPS."),
    ("Lt Gen Puleng Dimpane", "Lt Gen", 1, None, 1, "SAPS CFO. Acted as National Commissioner from Apr 2026."),
    ("Minister Senzo Mchunu", "Mr", 1, 99, 0, "Minister of Police. Political head of SAPS."),
    ("Shamila Batohi", "Adv", 0, None, 1, "Former NDPP. Appointed 2019, succeeded by Mothibi."),
    ("Adv Andy JL Mothibi", "Adv", 0, None, 1, "Current NDPP. Accounting Officer for NPA. IDAC reports to him."),
    ("Gen Shadrack Sibiya", "Gen", 1, None, 1, "Suspended Deputy National Commissioner: Crime Detection. IDAC investigated him."),
    ("Lt Gen Dumisani Khumalo", "Lt Gen", 1, 24, 1, "SAPS Lt Gen. Arrested by IDAC. Subject of 'Khan-IDAC cabal' allegations."),
    ("Chief Mapiyeye", "Chief", 1, 68, 1, "Chief of Police EMPD. Subject of disciplinary proceedings."),
    ("Ms Linda Gxasheka", "Ms", 1, 131, 0, "HOD Human Resources at Ekurhuleni."),
    ("Justice Mbuyiseli Madlanga", "Justice", 0, None, 0, "Chairperson of the commission."),
    ("Adv Annemarie Friedman", "Adv", 0, None, 0, "Deputy Director of Public Prosecutions at IDAC."),
    ("Mr Nciza", "Mr", 1, 73, 0, "HOD Employee Relations at Ekurhuleni."),
    ("Mr Magagula", "Mr", 1, 135, 0, "Ekurhuleni witness."),
    ("Adv Behari", "Adv", 1, None, 0, "HOD Legal at Ekurhuleni."),
    ("Lt Gen Francinah Vuma", "Lt Gen", 1, None, 1, "Deputy National Commissioner SAPS. Retired Feb 2026."),
    ("Maj Gen Solly Lazarus", "Maj Gen", 0, None, 1, "CFO of SAPS Crime Intelligence. Investigated by IDAC."),
    ("Mr Paul O'Sullivan", "Mr", 1, 231, 0, "Whistleblower. Testified at Mkhwanazi Inquiry."),
])

people_map = {}
for r in c.execute("SELECT id, full_name FROM people").fetchall():
    people_map[r[1]] = r[0]

# ── Seed: Positions ────────────────────────────────
c.executemany("INSERT INTO positions (person_id, institution_id, title, is_accounting_officer, is_cfo, start_date, end_date, budget_authority, budget_authority_type, appointed_by, source, notes) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", [
    # Mashazi career
    (people_map["Dr Imogen Mashazi"], inst_map["Ekurhuleni"], "City Manager", 1, 0, "2016", "2025-07-31", 1, "accounting_officer", "Council", "PMG 2019 Q&A; Day 41 testimony", "Two terms. First ended 2021, reappointed."),
    # Andrea Johnson
    (people_map["Adv Andrea Johnson"], inst_map["IDAC"], "Special Director / Head of IDAC", 0, 0, "~2021/22", "2026-07-26", 1, "head_of_unit", "NDPP", "NPA website; News24", "Resigned same day as testifying."),
    # SAPS leadership
    (people_map["Lt Gen Nhlanhla Mkhwanazi"], inst_map["SAPS"], "National Commissioner", 1, 0, "~2024/25", None, 1, "accounting_officer", "President", "Commission testimony", "Current National Commissioner."),
    (people_map["Gen Fannie Masemola"], inst_map["SAPS"], "National Commissioner", 1, 0, "~2020", "~2024/25", 1, "accounting_officer", "President", "PMG: Ad Hoc Committee 17 Mar 2026", "Predecessor to Mkhwanazi."),
    (people_map["Lt Gen Puleng Dimpane"], inst_map["SAPS"], "Chief Financial Officer", 0, 1, "~2022", None, 1, "cfo", "National Commissioner", "PMG: Mkhwanazi Inquiry 25 Nov 2025", "Also acted as National Commissioner from Apr 2026."),
    (people_map["Gen Shadrack Sibiya"], inst_map["SAPS"], "Deputy National Commissioner: Crime Detection", 0, 0, "~2018", "~2025", 0, None, "National Commissioner", "PMG: Ad Hoc Committee 13-14 Oct 2025", "Suspended."),
    (people_map["Lt Gen Francinah Vuma"], inst_map["SAPS"], "Deputy National Commissioner", 0, 0, "2017-12", "2026-02", 0, None, "National Commissioner", "PMG: Ad Hoc Committee 11 Mar 2026", "Retired Feb 2026."),
    (people_map["Maj Gen Solly Lazarus"], inst_map["Crime Intelligence"], "Chief Financial Officer", 0, 1, "~2020", None, 1, "cfo", "SAPS National Commissioner", "Commission testimony Day 144", "Investigated by IDAC."),
    # NPA leadership
    (people_map["Shamila Batohi"], inst_map["NPA"], "National Director of Public Prosecutions (NDPP)", 1, 0, "2019", "~2023/24", 1, "accounting_officer", "President", "Public record", "Appointed post-state capture."),
    (people_map["Adv Andy JL Mothibi"], inst_map["NPA"], "National Director of Public Prosecutions (NDPP)", 1, 0, "~2024", None, 1, "accounting_officer", "President", "NPA website", "Current NDPP. Johnson resigned to him."),
    # Ekurhuleni
    (people_map["Chief Mapiyeye"], inst_map["EMPD"], "Chief of Police", 0, 0, "~2020", None, 0, None, "City Manager", "Commission testimony Days 41-42", "Subject of sexual harassment allegations."),
    (people_map["Ms Linda Gxasheka"], inst_map["Ekurhuleni"], "HOD: Human Resources", 0, 0, "~2020", None, 0, None, "City Manager", "Commission testimony", "Oversaw HR processes including appointments."),
])

# ── Seed: Audit Outcomes ───────────────────────────
c.executemany("INSERT INTO audit_outcomes (institution_id, financial_year, audit_opinion, has_findings, material_irregularities, irregular_expenditure_details, supply_chain_findings, source) VALUES (?,?,?,?,?,?,?,?)", [
    # SAPS
    (inst_map["SAPS"], "2023/24", "unqualified_clean", 1, "Ineffective management of 10111 call centres", "Present — under assessment, determination, and investigation", 1, "SAPS Annual Report 2023/24"),
    (inst_map["SAPS"], "2024/25", "unqualified_clean", 1, "Material irregularities listed in AGSA report", "Present", 1, "SAPS Annual Report 2024/25"),
    # NPA
    (inst_map["NPA"], "2023/24", "unqualified_findings", 1, "Justice portfolio: no entity had clean audit", "Persistent irregular expenditure flagged", 1, "PMG: Justice Portfolio 15 Oct 2025; NPA AR 2023/24"),
    (inst_map["NPA"], "2024/25", "unqualified_findings", 1, "Continued pattern of unauthorised expenditure", "Present", 1, "PMG: Justice Portfolio/NA Hansard 4 Nov 2025"),
])

# ── Seed: Witness Topics ───────────────────────────
c.executemany("INSERT INTO witness_topics (witness_id, institution_id, day_numbers, key_topics, sentiment) VALUES (?,?,?,?,?)", [
    (people_map["Dr Imogen Mashazi"], inst_map["Ekurhuleni"], "41, 42", "Political interference, EMPD discipline, contract awards, SAPS Act vs Municipal Systems Act", "critical"),
    (people_map["Dr Imogen Mashazi"], inst_map["EMPD"], "41, 42", "Chief Mapiyeye discipline, appointment irregularities, SAPS Act governance", "critical"),
    (people_map["Dr Imogen Mashazi"], inst_map["SAPS"], "41, 42", "SAPS Act application to EMPD", "neutral"),
    (people_map["Adv Andrea Johnson"], inst_map["IDAC"], "144", "IDAC mandate, death threats, arrest of Khumalo, Khan-IDAC cabal allegations", "defensive"),
    (people_map["Colonel Padayachee"], inst_map["IDAC"], "139, 140, 141", "IDAC investigation processes, section 27 referrals, docket management", "defensive"),
    (people_map["Colonel Padayachee"], inst_map["SAPS"], "139, 140, 141", "IDAC investigations into SAPS, Crime Intelligence, appointment panels", "critical"),
    (people_map["Lt Gen Nhlanhla Mkhwanazi"], inst_map["SAPS"], "1, 3, 4", "Corruption allegations, political interference, IPID reports, Task Team", "defensive"),
    (people_map["Lt Gen Dumisani Khumalo"], inst_map["SAPS"], "multiple", "Arrested by IDAC, mandate of IDAC questioned", "critical"),
    (people_map["Chief Mapiyeye"], inst_map["EMPD"], "multiple", "Governance of EMPD, appointment panels, relationship with Mashazi", "critical"),
])

# ── Seed: Allegations (key ones from research) ─────
c.executemany("INSERT INTO allegations (witness_id, target_institution_id, target_person_id, category, severity, summary, day_number, context_snippet, corroborated_by) VALUES (?,?,?,?,?,?,?,?,?)", [
    (people_map["Dr Imogen Mashazi"], inst_map["Ekurhuleni"], None, "capture", "critical", "Mayor and MMC Finance pressured her to stop disciplinary process against Chief of Police over sexual harassment allegations", 42, "the Mayor called me and indicated that I should stop the process of disciplining...", "Council resolution IM25"),
    (people_map["Dr Imogen Mashazi"], inst_map["Ekurhuleni"], people_map["Chief Mapiyeye"], "corruption", "high", "Chief Mapiyeye appointed a single law firm (Zebediela Attorneys) with exorbitant fee structures, never won a case", 42, "Mr Nciza has a history of appointing one single firm, which is Zebediela Attorneys... the fees were exorbitant", "testimony cross-examination"),
    (people_map["Adv Andrea Johnson"], inst_map["IDAC"], None, "mixed", "high", "Denied existence of 'Khan-IDAC cabal' and defended IDAC's mandate against allegations of overreach", 144, "I deny these allegations. They are baseless and devoid of merit.", "Col Padayachee's earlier testimony"),
])

# ── Seed: Cross-Institutional Moves ────────────────
c.executemany("INSERT INTO cross_institutional_moves (person_id, from_institution_id, to_institution_id, from_role, to_role, move_date, pattern_type, source) VALUES (?,?,?,?,?,?,?,?)", [
    (people_map["Dr Imogen Mashazi"], inst_map["Ekurhuleni"], inst_map["SAPS"], "City Manager (Accounting Officer)", "HOD (Head of Department)", "2025-08-01", "municipal_to_national", "User inference — needs confirmation"),
])

# ── Seed: Conflicts of Interest ────────────────────
c.executemany("INSERT INTO conflicts_of_interest (title, institution_primary_id, institution_secondary_id, category, severity, source, detail, commission_mention) VALUES (?,?,?,?,?,?,?,?)", [
    ("IDAC staffed by secondments from institutions it investigates", inst_map["IDAC"], inst_map["SAPS"], "structural", "critical", "NPA website", "IDAC includes secondments from SAPS, SSA, DPCI, SARS, IPID. Investigators borrowed from bodies they must scrutinize. Creates loyalty conflicts.", 1),
    ("IDAC Head reports to NDPP who controls IDAC budget", inst_map["IDAC"], inst_map["NPA"], "financial", "high", "NPA annual reports", "Johnson reports to Mothibi (NDPP) who is Accounting Officer for NPA budget including IDAC. No financial independence.", 1),
    ("Mothibi named in Johnson resignation alongside Ramaphosa", inst_map["NPA"], None, "political", "high", "News24", "Johnson asked both President and NDPP to resign. Suggests NDPP not independent from political influence.", 1),
    ("NPA fails own audits while prosecuting financial crimes", inst_map["NPA"], None, "structural", "high", "PMG Justice Portfolio 15 Oct 2025", "Justice portfolio including NPA had no clean audit. Institution prosecuting financial misconduct cannot pass its own audit.", 1),
    ("Commission witness claimed IDAC operating outside mandate", inst_map["IDAC"], inst_map["SAPS"], "structural", "critical", "Commission transcript Day 2", "Sources within IDAC said activities not in line with mandate. Justice Madlanga questioned if IDAC had 'arrogated power over SAPS'.", 1),
    ("Chairperson questioned IDAC overreach", inst_map["IDAC"], inst_map["SAPS"], "structural", "critical", "Commission transcript Day 141", "Justice Madlanga asked Col Padayachee: 'IDAC has arrogated to itself the power to be an overseer over SAPS. Is that what you are saying?'", 1),
])

conn.commit()

# ── Verify ─────────────────────────────────────────
print("=== Database Built Successfully ===")
for table in ["institutions", "people", "positions", "allocations", "allocation_authorizers",
              "audit_outcomes", "witness_topics", "allegations", "cross_institutional_moves",
              "conflicts_of_interest", "conspirator_links", "sources"]:
    count = c.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"  {table:30s}: {count:3d} rows")

print(f"\nDatabase: {DB_PATH}")
db_size = DB_PATH.stat().st_size / 1024
print(f"Size: {db_size:.0f} KB")

# Reopen with row factory for verification queries
conn.close()
conn = sqlite3.connect(str(DB_PATH))
conn.row_factory = sqlite3.Row
c = conn.cursor()

# ── Query examples ─────────────────────────────────
print("\n=== Cross-Institutional Moves ===")
for r in c.execute("""
    SELECT p.full_name, i1.abbreviation AS from_i, i2.abbreviation AS to_i,
           cm.from_role, cm.to_role, cm.pattern_type
    FROM cross_institutional_moves cm
    JOIN people p ON p.id = cm.person_id
    JOIN institutions i1 ON i1.id = cm.from_institution_id
    JOIN institutions i2 ON i2.id = cm.to_institution_id
"""):
    print(f"  {r['full_name'][:25]:25s} {r['from_i']:15s} -> {r['to_i']:15s} | {r['from_role'][:20]} -> {r['to_role']}")

print("\n=== Conflict Severity Summary ===")
for r in c.execute("SELECT severity, COUNT(*) FROM conflicts_of_interest GROUP BY severity ORDER BY severity"):
    print(f"  {r[0]:8s}: {r[1]}")

conn.close()
