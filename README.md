# Madlanga Commission Research Dashboard

An intelligence dashboard for the **Judicial Commission of Inquiry into Criminality, Political Interference and Corruption in the Criminal Justice System** (South Africa). It turns 144+ days of public hearing transcripts, witness statements and commission documents into a searchable, connected research workspace for investigators, journalists and legal teams.

## What it does

- **Full-text search** across every transcript, statement and document (SQLite FTS5), with citations ("Day 47, p.23, lines 10–15") and CSV citation export
- **Case Network** — an interactive bipartite graph of witnesses and the organisations/cases/locations/money they implicated
- **Attention Map** — a heatmap of which entities each witness focused on
- **Story Map** — parallel timelines of commission evidence vs witness testimony
- **Witness & Entity profiles** — roles, organisations, mention counts, connected evidence
- **Evidence Compare** — side-by-side testimony, documents and witness statements, with a downloadable, printable Evidence Bundle
- **Contradictions** — entities where one witness affirms something and another denies it, shown side by side with the wording highlighted
- **Notes** — shared team notes and "flag as incorrect" reports on any search result or testimony excerpt
- **Dashboard** — accusation statistics, severity categories, corroboration and reliability scoring
- **Institutions** — leadership, AGSA audit outcomes, allegations and conflicts of interest per state institution (IDAC, NPA, SAPS, City of Ekurhuleni), with the research still missing for each

## Architecture

```
madlanga_downloader.py          # Downloads all public records from the Commission's site
commission_research/
  inquiries/<id>/inquiry.json   # One inquiry: names, speakers, focus witness, branding
  packs/<country>.json          # One jurisdiction: organisations, places, case/money formats
  pipeline/                     # Python: parse → normalize → extract → index → build
    inquiry_config.py           #   loads + validates the inquiry config and its pack
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
    inquiry.R                   #   inquiry settings, publishing disclaimer
    auth.R                      #   customer logins, roles, Users tab
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

`build_db.py` runs every step, including `institutions` (the institutional
analysis database). A single step can be re-run with e.g. `build_db.py institutions`.
Rebuild the database after pulling these changes so transcript citations get
their page and line numbers.

### 3. Launch the dashboard

Requires [R 4.x](https://cran.r-project.org) with the packages in `commission_research/R_requirements.txt`.

```bash
cd commission_research
.\run.bat          # Windows
# or
Rscript -e "shiny::runApp('app', launch.browser=TRUE)"
```

The dashboard checks its license and asks for a login on every session. For
local development either set `MADLANGA_DEV_MODE=true` (environment variable or
`app/.Renviron`), or generate a license and create a user for yourself (see
Licensing and Logins below).

### 4. Run the tests

```bash
pip install pytest && pytest commission_research/tests/python
Rscript -e 'testthat::test_dir("commission_research/tests/r")'
```

## Licensing

**Copyright (c) 2026 Unarine Masiavhula. All rights reserved.** This software is
the exclusive property of Unarine Masiavhula and is licensed under a proprietary
license — see [`LICENSE`](LICENSE). Use, modification, or redistribution requires
a separate Commercial License from the copyright holder.

The dashboard also ships with a signed license system (`tools/generate_license.py`,
`app/license_check.r`). The HMAC signing secret is read from the
`MADLANGA_LICENSE_SECRET` environment variable or a gitignored `.license_secret`
file — never hardcoded.

- License checks are **on by default**. A missing, unsigned or tampered
  `license.key`, a missing secret, or an expired license (after a 14-day grace
  period) blocks the dashboard. `MADLANGA_DEV_MODE=true` skips the check.
- Issue a license: `python tools/generate_license.py "Customer" --tier professional --months 12 --output commission_research/app/license.key`
- Renew with fresh data: `python tools/update_and_renew.py --customer "Customer" --tier professional`
- `license.key` files are per customer and gitignored; never commit one.
- To deploy (e.g. shinyapps.io), put `license.key` and an `.Renviron` containing
  `MADLANGA_LICENSE_SECRET=...` in `commission_research/app/` before deploying.
  Optionally set `MADLANGA_LICENSE_URL` to the `/api/check-license` endpoint of
  `tools/license_server.py` to enable remote revocation.
- Team notes are stored in `app/data/annotations.db`. On hosts with a temporary
  disk (shinyapps.io wipes it on every redeploy or restart) set
  `MADLANGA_ANNOTATIONS_DB` to a path on persistent storage.

## Running another inquiry

Nothing about Madlanga is hard-coded any more. To set up a new inquiry:

1. Copy `commission_research/inquiries/madlanga/inquiry.json` to
   `inquiries/<new-id>/inquiry.json` and edit it: names, `source_dir` (where its
   `transcripts_txt/`, `hearings/` and `metadata/` live), the speaker rules
   (`[regex, canonical name, role]`, first match wins, `{1}` = first regex
   group), the focus witness shown at the centre of the network, exhibit
   numbering, branding and support contact.
2. Pick a jurisdiction pack (`packs/za.json` for South Africa) or copy one for a
   new country.
3. Build: `INQUIRY_CONFIG=commission_research/inquiries/<new-id>/inquiry.json python commission_research/pipeline/build_db.py`.
   The first step validates the config and writes `app/inquiry.json`, which is
   what the deployed dashboard reads.

Every screen carries a publishing disclaimer (a mention is not a finding of
wrongdoing; check the cited transcript before publishing). An inquiry can
reword it with a `"disclaimer"` key but cannot remove it.

## Logins

Each deployment has its own accounts, stored in `app/data/users.db` (or
`MADLANGA_USERS_DB`) with scrypt-hashed passwords. Roles: **admin** (everything
plus the Users tab), **analyst** (read, add notes and flags), **viewer** (read
only). Five wrong passwords lock an account for 15 minutes; sessions last 12
hours.

```bash
Rscript tools/manage_users.R add alice --role admin --name "Alice M"   # first admin
Rscript tools/manage_users.R list
Rscript tools/manage_users.R password alice      # also signs alice out everywhere
Rscript tools/manage_users.R disable bob
```

After that, admins add and manage users in the dashboard's **Users** tab.
Ship `users.db` with the app or point `MADLANGA_USERS_DB` at persistent storage
(on shinyapps.io the app disk is wiped on redeploy). `MADLANGA_AUTH=off` turns
logins off, e.g. behind a host that already authenticates users;
`MADLANGA_DEV_MODE=true` also skips them.

## Repository notes

- Raw transcripts, statements and the SQLite databases are **not** committed (see `.gitignore`); run the downloader and pipeline to regenerate them.
