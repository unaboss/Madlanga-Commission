# Madlanga Commission Research Dashboard

An intelligence dashboard for the **Judicial Commission of Inquiry into Criminality, Political Interference and Corruption in the Criminal Justice System** (South Africa). It turns 144+ days of public hearing transcripts, witness statements and commission documents into a searchable, connected research workspace for investigators, journalists and legal teams.

## What it does

- **Full-text search** across every transcript, statement and document (SQLite FTS5)
- **Case Network** — an interactive bipartite graph of witnesses and the organisations/cases/locations/money they implicated
- **Attention Map** — a heatmap of which entities each witness focused on
- **Story Map** — parallel timelines of commission evidence vs witness testimony
- **Witness & Entity profiles** — roles, organisations, mention counts, connected evidence
- **Evidence Compare** — side-by-side testimony, documents and witness statements
- **Contradictions** — flagged inconsistencies between witnesses and across hearings
- **Dashboard** — accusation statistics, severity categories, corroboration and reliability scoring
- **Institutional analysis** — a linked database tracking budget allocations, leadership and audit outcomes across state institutions (IDAC, NPA, SAPS, City of Ekurhuleni)

## Architecture

```
madlanga_downloader.py          # Downloads all public records from the Commission's site
commission_research/
  pipeline/                     # Python: parse → normalize → extract → index → build
    parse_transcripts.py        #   speaker-labelled transcript parsing
    normalize_speakers.py       #   alias/role normalisation
    extract_entities.py         #   organisations, people, cases, exhibits, locations
    index_search.py             #   SQLite + FTS5 search index
    build_db.py                 #   orchestrates the whole pipeline
    compute_network.py          #   accusation/network graph → network_data.json
    build_story_map.py          #   evidence/testimony timelines → story_map_data.json
    build_institutional_db.py   #   institutional_analysis.db schema + seed data
  data/                         # SQLite databases (gitignored)
  app/                          # R / Shiny dashboard
    app.R                       #   UI + server (bslib, visNetwork, plotly, reactable)
    global.R                    #   data access + dashboard logic
  research/                     # institutional research notes & briefs
```

The pipeline produces a SQLite database plus JSON datasets (`network_data.json`, `story_map_data.json`, `attention_matrix.json`) which the R/Shiny app loads.

## Getting started

### 1. Download the data

```bash
python madlanga_downloader.py --metadata-only
python madlanga_downloader.py
```

### 2. Build the database

```bash
python commission_research/pipeline/build_db.py
python commission_research/pipeline/compute_network.py
python commission_research/pipeline/build_story_map.py
```

### 3. Launch the dashboard

Requires [R 4.x](https://cran.r-project.org) with the packages in `commission_research/R_requirements.txt`.

```bash
cd commission_research
.\run.bat          # Windows
# or
Rscript -e "shiny::runApp('app', launch.browser=TRUE)"
```

## Licensing

The dashboard ships with a signed license system (`tools/generate_license.py`, `tools/license_check.r`). The HMAC signing secret is read from the `MADLANGA_LICENSE_SECRET` environment variable or a gitignored `.license_secret` file — never hardcoded.

## Repository notes

- Raw transcripts, statements and the SQLite databases are **not** committed (see `.gitignore`); run the downloader and pipeline to regenerate them.
- The `business/` folder contains the business pitch, value analysis and media collaboration documents for the OpenEyeDataAnalyst offering.
