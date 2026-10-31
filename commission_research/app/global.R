# global.R — Commission Research Tool — Shared logic
library(DBI)
library(RSQLite)
library(dplyr)
library(lubridate)
library(stringr)
library(jsonlite)

# ── License check ────────────────────────────────────────────────
# The license is validated per session in server() so a renewed
# license.key takes effect on reload without restarting the app.
source("license_check.r")

# ── Inquiry settings (names, branding, focus witness, disclaimer) ─────
source("inquiry.R")

# ── Customer logins ──────────────────────────────────────────────
source("auth.R")

# ── Paths ───────────────────────────────────────────────────────
APP_DIR  <- getwd()
DB_PATH <- normalizePath(file.path(APP_DIR, "data", "commission_research.db"), mustWork = FALSE)
NETWORK_PATH   <- file.path(APP_DIR, "www", "network_data.json")
ATTENTION_PATH <- file.path(APP_DIR, "www", "attention_matrix.json")
STORYMAP_PATH  <- file.path(APP_DIR, "www", "story_map_data.json")
# Institutional analysis DB: copied into app/data for deployment, or read
# straight from the pipeline output when running from the repo.
INSTITUTIONAL_DB_CANDIDATES <- c(
  file.path(APP_DIR, "data", "institutional_analysis.db"),
  file.path(APP_DIR, "..", "data", "institutional_analysis.db")
)
# Shared notes/flags. Point MADLANGA_ANNOTATIONS_DB at persistent storage
# when the app runs on a host with an ephemeral disk (e.g. shinyapps.io).
ANNOTATIONS_DB_PATH <- Sys.getenv("MADLANGA_ANNOTATIONS_DB",
  unset = file.path(APP_DIR, "data", "annotations.db"))

# ── Helpers ──────────────────────────────────────────────────────
escape_html <- function(x) {
  if (is.null(x) || is.na(x)) return("")
  x <- as.character(x)
  x <- gsub("&", "&amp;", x)
  x <- gsub("<", "&lt;", x)
  x <- gsub(">", "&gt;", x)
  x <- gsub("\"", "&quot;", x)
  x <- gsub("'", "&#39;", x)
  x
}

# ── Citations ────────────────────────────────────────────────────
# Transcript citations in the commission's format: "Day 47, p.23, lines 10–15".
# Page/line data comes from parse_transcripts.py; rows from databases built
# before it existed have zeros and fall back to the day (and page) only.
format_citation <- function(day, page = 0, line_start = 0, page_end = page, line_end = line_start) {
  n <- max(length(day), 1)
  num <- function(x) {
    x <- suppressWarnings(as.integer(x))
    if (length(x) == 0) x <- NA_integer_
    x <- rep_len(x, n)
    x[is.na(x)] <- 0L
    x
  }
  day <- num(day); page <- num(page); line_start <- num(line_start)
  page_end <- num(page_end); line_end <- num(line_end)
  page_end[page_end == 0] <- page[page_end == 0]
  line_end[line_end == 0] <- line_start[line_end == 0]

  out <- character(n)
  for (i in seq_len(n)) {
    if (day[i] <= 0) next
    cite <- paste0("Day ", day[i])
    if (page[i] > 0) {
      if (line_start[i] <= 0) {
        cite <- paste0(cite, if (page_end[i] > page[i])
          paste0(", pp.", page[i], "\u2013", page_end[i]) else paste0(", p.", page[i]))
      } else if (page_end[i] > page[i]) {
        cite <- paste0(cite, ", p.", page[i], " line ", line_start[i],
                       " \u2013 p.", page_end[i], " line ", line_end[i])
      } else if (line_end[i] > line_start[i]) {
        cite <- paste0(cite, ", p.", page[i], ", lines ", line_start[i], "\u2013", line_end[i])
      } else {
        cite <- paste0(cite, ", p.", page[i], ", line ", line_start[i])
      }
    }
    out[i] <- cite
  }
  out
}

# SELECT fragment for the citation columns of `table`, using 0 for columns
# an older database does not have.
citation_columns_sql <- function(conn, table, alias) {
  cols <- dbListFields(conn, table)
  pick <- function(col, fallback = "0") if (col %in% cols) paste0(alias, ".", col) else fallback
  paste0(pick("page_number"), " AS page_number, ",
         pick("line_start"), " AS line_start, ",
         pick("page_end", pick("page_number")), " AS page_end, ",
         pick("line_end"), " AS line_end")
}

add_citations <- function(df, day_col = "day_number") {
  if (is.null(df) || nrow(df) == 0) {
    if (!is.null(df)) df$citation <- character(0)
    return(df)
  }
  df$citation <- format_citation(df[[day_col]], df$page_number %||% 0,
                                 df$line_start %||% 0, df$page_end %||% 0,
                                 df$line_end %||% 0)
  df
}

citations_csv <- function(df) {
  out <- data.frame(
    citation = df$citation %||% character(0),
    date = df$date %||% df$hearing_date %||% rep("", nrow(df)),
    speaker = df$speaker %||% rep("", nrow(df)),
    excerpt = gsub("\\s+", " ", df$text %||% df$preview %||% df$context_text %||% rep("", nrow(df))),
    stringsAsFactors = FALSE
  )
  out
}

# ── DB Connection ───────────────────────────────────────────────
get_db <- function() {
  if (!file.exists(DB_PATH)) stop("Database not found at: ", DB_PATH)
  dbConnect(SQLite(), DB_PATH)
}

# ── Load network data ───────────────────────────────────────────
network_cache <- NULL
load_network <- function() {
  if (is.null(network_cache)) {
    txt <- paste(readLines(NETWORK_PATH, warn = FALSE), collapse = "\n")
    network_cache <<- parse_json(txt)
  }
  network_cache
}

attention_cache <- NULL
load_attention <- function() {
  if (is.null(attention_cache)) {
    txt <- paste(readLines(ATTENTION_PATH, warn = FALSE), collapse = "\n")
    attention_cache <<- parse_json(txt)
  }
  attention_cache
}

storymap_cache <- NULL
load_story_map <- function() {
  if (is.null(storymap_cache)) {
    if (file.exists(STORYMAP_PATH)) {
      txt <- paste(readLines(STORYMAP_PATH, warn = FALSE), collapse = "\n")
      storymap_cache <<- parse_json(txt)
    } else {
      storymap_cache <<- list(
        commission_timeline = list(),
        witness_timeline = list(),
        unique_witnesses = list(),
        shared_entities = list(),
        all_entities = list(),
        stats = list(total_commission_events = 0, total_witness_slots = 0,
                     total_hearing_days = 0, date_range = list(first = "", last = ""))
      )
    }
  }
  storymap_cache
}

# ── Data access functions ───────────────────────────────────────

search_fts <- function(conn, query, date_from = NULL, date_to = NULL,
                       speaker = NULL, limit = 60) {
  sql <- paste0(
    "SELECT source, source_id, title, date, speaker, ",
    "snippet(search_index, 3, '<mark>', '</mark>', '...', 45) AS snippet, ",
    "substr(text, 1, 400) AS preview, text ",
    "FROM search_index WHERE search_index MATCH ?"
  )
  params <- list(query)
  if (!is.null(date_from) && nzchar(date_from)) {
    sql <- paste0(sql, " AND date >= ?"); params <- c(params, list(date_from))
  }
  if (!is.null(date_to) && nzchar(date_to)) {
    sql <- paste0(sql, " AND date <= ?"); params <- c(params, list(date_to))
  }
  if (!is.null(speaker) && nzchar(speaker)) {
    sql <- paste0(sql, " AND speaker LIKE ?"); params <- c(params, list(paste0("%", speaker, "%")))
  }
  sql <- paste0(sql, " LIMIT ?"); params <- c(params, list(limit))
  sql <- paste0(
    "SELECT r.*, h.day_number, ", citation_columns_sql(conn, "transcript_segments", "ts"),
    " FROM (", sql, ") r",
    " LEFT JOIN transcript_segments ts ON r.source = 'transcript' AND ts.id = r.source_id",
    " LEFT JOIN hearings h ON h.id = ts.hearing_id"
  )
  df <- add_citations(as.data.frame(dbGetQuery(conn, sql, params = params)))
  if (nrow(df) > 0) {
    no_cite <- !nzchar(df$citation)
    df$citation[no_cite] <- ifelse(df$source[no_cite] == "statement",
      paste0("Statement: ", df$title[no_cite]), df$title[no_cite])
  }
  df
}

get_hearings <- function(conn) {
  as.data.frame(dbGetQuery(conn,
    "SELECT day_number, hearing_date, summary FROM hearings ORDER BY day_number"))
}

get_witness_segments <- function(conn, speaker_name) {
  add_citations(as.data.frame(dbGetQuery(conn, paste0(
    "SELECT h.day_number, h.hearing_date, ts.text, ",
    citation_columns_sql(conn, "transcript_segments", "ts"), "
     FROM transcript_segments ts
     JOIN speakers s ON s.id = ts.speaker_id
     JOIN hearings h ON h.id = ts.hearing_id
     WHERE s.canonical_name LIKE ?
     ORDER BY h.day_number, ts.id
     LIMIT 500"),
    params = list(paste0("%", speaker_name, "%"))
  )))
}

get_speaker_stats <- function(conn) {
  as.data.frame(dbGetQuery(conn,
    "SELECT s.canonical_name, s.role, COUNT(ts.id) AS segments,
            COUNT(DISTINCT ts.hearing_id) AS days
     FROM speakers s
     JOIN transcript_segments ts ON ts.speaker_id = s.id
     GROUP BY s.id ORDER BY segments DESC"))
}

get_top_entities <- function(conn, etype = NULL, limit = 30) {
  sql <- "SELECT entity_type, entity_value, COUNT(*) AS cnt FROM entities"
  params <- list()
  if (!is.null(etype)) {
    sql <- paste0(sql, " WHERE entity_type = ?")
    params <- c(params, list(etype))
  }
  sql <- paste0(sql, " GROUP BY entity_type, entity_value ORDER BY cnt DESC LIMIT ?")
  params <- c(params, list(limit))
  as.data.frame(dbGetQuery(conn, sql, params = params))
}

get_entity_context <- function(conn, entity_value, limit = 100) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.context_text, h.hearing_date, h.day_number, s.canonical_name AS speaker,
            e.source AS source_type
     FROM entities e
     LEFT JOIN hearings h ON h.id = e.hearing_id
     LEFT JOIN speakers s ON s.id = e.speaker_id
     WHERE e.entity_value = ?
     ORDER BY h.day_number
     LIMIT ?",
    params = list(entity_value, limit)
  ))
}

get_entity_mentions <- function(conn, entity_value, limit = 200) {
  df <- add_citations(as.data.frame(dbGetQuery(conn, paste0(
    "SELECT e.id, e.entity_type, e.entity_value, e.context_text,
            h.hearing_date, h.day_number,
            s.canonical_name AS speaker, s.role AS speaker_role,
            e.source AS source_type, ",
    citation_columns_sql(conn, "entities", "e"), "
     FROM entities e
     LEFT JOIN hearings h ON h.id = e.hearing_id
     LEFT JOIN speakers s ON s.id = e.speaker_id
     WHERE LOWER(e.entity_value) = LOWER(?)
     ORDER BY h.hearing_date
     LIMIT ?"),
    params = list(entity_value, limit)
  )))
  # Statement mentions are not transcript lines, so cite the source instead
  if (nrow(df) > 0) {
    stmt <- df$source_type != "transcript"
    df$citation[stmt] <- paste0("Statement: ", df$speaker[stmt] %||% "")
  }
  df
}

get_person_entities <- function(conn, speaker_id, limit = 20) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.entity_value, e.entity_type, COUNT(*) AS cnt
     FROM entities e
     WHERE e.speaker_id = ?
     GROUP BY e.entity_value
     ORDER BY cnt DESC
     LIMIT ?",
    params = list(speaker_id, limit)
  ))
}

get_entity_witnesses <- function(conn, entity_value, limit = 20) {
  as.data.frame(dbGetQuery(conn,
    "SELECT s.canonical_name, s.role, COUNT(*) AS cnt
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     WHERE e.entity_value = ?
     GROUP BY e.speaker_id
     ORDER BY cnt DESC
     LIMIT ?",
    params = list(entity_value, limit)
  ))
}

get_entity_snippets <- function(conn, speaker_id, entity_value, limit = 3) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.context_text, h.hearing_date, h.day_number
     FROM entities e
     LEFT JOIN hearings h ON h.id = e.hearing_id
     WHERE e.speaker_id = ? AND LOWER(e.entity_value) = LOWER(?)
     LIMIT ?",
    params = list(speaker_id, entity_value, limit)
  ))
}

get_org_detail_witnesses <- function(conn, org_value) {
  as.data.frame(dbGetQuery(conn,
    "SELECT
       (SELECT COUNT(DISTINCT e1.speaker_id) FROM entities e1
        WHERE e1.entity_type = 'organization' AND e1.entity_value = ?) AS witness_count,
       (SELECT COUNT(DISTINCT e2.entity_value) FROM entities e1
        JOIN entities e2 ON e1.speaker_id = e2.speaker_id AND e1.hearing_id = e2.hearing_id
        WHERE e1.entity_type = 'organization' AND e1.entity_value = ?
          AND e2.entity_type = 'case_reference') AS case_count,
       (SELECT COUNT(DISTINCT e2.entity_value) FROM entities e1
        JOIN entities e2 ON e1.speaker_id = e2.speaker_id AND e1.hearing_id = e2.hearing_id
        WHERE e1.entity_type = 'organization' AND e1.entity_value = ?
          AND e2.entity_type = 'location') AS location_count",
    params = list(org_value, org_value, org_value)
  ))
}

get_org_locations <- function(conn, org_value, limit = 20) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e2.entity_value AS location, COUNT(DISTINCT e1.speaker_id) AS witnesses
     FROM entities e1
     JOIN entities e2 ON e1.speaker_id = e2.speaker_id AND e1.hearing_id = e2.hearing_id
     WHERE e1.entity_type = 'organization' AND e1.entity_value = ?
       AND e2.entity_type = 'location'
     GROUP BY e2.entity_value
     ORDER BY witnesses DESC
     LIMIT ?",
    params = list(org_value, limit)
  ))
}

get_org_cases <- function(conn, org_value, limit = 20) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e2.entity_value AS case_ref, COUNT(DISTINCT e1.speaker_id) AS witnesses
     FROM entities e1
     JOIN entities e2 ON e1.speaker_id = e2.speaker_id AND e1.hearing_id = e2.hearing_id
     WHERE e1.entity_type = 'organization' AND e1.entity_value = ?
       AND e2.entity_type = 'case_reference'
     GROUP BY e2.entity_value
     ORDER BY witnesses DESC
     LIMIT ?",
    params = list(org_value, limit)
  ))
}

get_speaker_profiles <- function(conn) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.speaker_id, s.canonical_name, s.role,
            e.entity_value, e.entity_type, COUNT(*) AS cnt
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     WHERE s.role IN ('witness', 'witness_protected', 'evidence_leader', 'commissioner')
     GROUP BY e.speaker_id, e.entity_value
     HAVING cnt >= 2
     ORDER BY e.speaker_id, cnt DESC"
  ))
}

get_accusation_stats <- function(conn) {
  as.data.frame(dbGetQuery(conn,
    "SELECT entity_type, COUNT(*) AS total_mentions,
            COUNT(DISTINCT entity_value) AS unique_entities
     FROM entities
     WHERE entity_type IN ('organization', 'case_reference', 'exhibit')
     GROUP BY entity_type
     ORDER BY total_mentions DESC"
  ))
}

get_top_accused <- function(conn, limit = 25) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.entity_value, e.entity_type, COUNT(*) AS mentions,
            COUNT(DISTINCT e.speaker_id) AS witnesses
     FROM entities e
     WHERE e.entity_type IN ('organization', 'case_reference', 'exhibit')
     GROUP BY e.entity_value, e.entity_type
     ORDER BY mentions DESC
     LIMIT ?",
    params = list(limit)))
}

# ── Premium: Witness Preparation Pack ────────────────────────────

get_witness_hearings <- function(conn, speaker_name) {
  as.data.frame(dbGetQuery(conn,
    "SELECT DISTINCT h.day_number, h.hearing_date, h.summary
     FROM transcript_segments ts
     JOIN speakers s ON s.id = ts.speaker_id
     JOIN hearings h ON h.id = ts.hearing_id
     WHERE s.canonical_name LIKE ?
     ORDER BY h.day_number",
    params = list(paste0("%", speaker_name, "%"))
  ))
}

get_witness_questioners <- function(conn, speaker_name) {
  as.data.frame(dbGetQuery(conn,
    "SELECT s2.canonical_name AS questioner, COUNT(*) AS interactions
     FROM transcript_segments ts
     JOIN speakers s ON s.id = ts.speaker_id
     JOIN transcript_segments ts2 ON ts2.hearing_id = ts.hearing_id
       AND ts2.id BETWEEN ts.id - 5 AND ts.id + 5
     JOIN speakers s2 ON s2.id = ts2.speaker_id
     WHERE s.canonical_name LIKE ?
       AND s2.role IN ('evidence_leader', 'commissioner')
       AND s2.id != s.id
     GROUP BY s2.canonical_name
     ORDER BY interactions DESC
     LIMIT 15",
    params = list(paste0("%", speaker_name, "%"))
  ))
}

# ── Premium: Contradiction Engine ────────────────────────────────
# Flags entities where one witness affirms something and another denies it.
# Stance is a keyword heuristic over each mention's context, so results are
# leads for a human to review, not findings.

DENIAL_PATTERN <- paste0(
  "\\b(deny|denied|denies|denying|denial|never|untrue|baseless|fabricat\\w*|",
  "not true|false|did not|didn't|was not|wasn't|were not|weren't|",
  "had nothing to do|not involved|no knowledge|not aware|unaware|",
  "dispute[sd]?|reject(?:ed)?|incorrect)\\b"
)
AFFIRM_PATTERN <- paste0(
  "\\b(confirm\\w*|admit\\w*|acknowledg\\w*|i saw|i was present|told me|",
  "instructed|received|paid|gave|handed|met with|i know|was involved|",
  "is true|that is correct|correct|yes)\\b"
)

# Denial wins over affirmation: "I never received" contains both.
classify_stance <- function(text) {
  t <- tolower(text %||% "")
  t[is.na(t)] <- ""
  den <- grepl(DENIAL_PATTERN, t, perl = TRUE)
  aff <- grepl(AFFIRM_PATTERN, t, perl = TRUE)
  ifelse(den, "denies", ifelse(aff, "affirms", "neutral"))
}

highlight_stance <- function(text) {
  out <- escape_html(text)
  out <- gsub(paste0("(?i)", DENIAL_PATTERN), "<mark class='deny'>\\1</mark>", out, perl = TRUE)
  gsub(paste0("(?i)", AFFIRM_PATTERN), "<mark class='affirm'>\\1</mark>", out, perl = TRUE)
}

# mentions: data.frame with entity_value, entity_type, witness, context_text.
# Returns one row per entity, contradictions first.
detect_contradictions <- function(mentions) {
  empty <- data.frame(entity_value = character(0), entity_type = character(0),
                      witness_count = integer(0), total_mentions = integer(0),
                      affirming = character(0), denying = character(0),
                      conflict_pairs = integer(0), stringsAsFactors = FALSE)
  if (is.null(mentions) || nrow(mentions) == 0) return(empty)
  mentions$stance <- classify_stance(mentions$context_text)
  rows <- lapply(split(mentions, mentions$entity_value), function(m) {
    aff <- sort(unique(m$witness[m$stance == "affirms"]))
    den <- sort(unique(m$witness[m$stance == "denies"]))
    # Pairs of different witnesses on opposite sides
    pairs <- sum(outer(aff, den, "!="))
    data.frame(
      entity_value = m$entity_value[1],
      entity_type = m$entity_type[1],
      witness_count = length(unique(m$witness)),
      total_mentions = nrow(m),
      affirming = paste(aff, collapse = ", "),
      denying = paste(den, collapse = ", "),
      conflict_pairs = as.integer(pairs),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(-out$conflict_pairs, -out$witness_count, -out$total_mentions), , drop = FALSE]
  rownames(out) <- NULL
  out
}

get_contradiction_candidates <- function(conn, min_witnesses = 2, entity_type = NULL,
                                         limit = 200) {
  sql <- "SELECT e.entity_value, e.entity_type,
            COUNT(DISTINCT e.speaker_id) AS witness_count,
            COUNT(*) AS total_mentions
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     WHERE s.role IN ('witness', 'witness_protected')"
  params <- list()
  if (!is.null(entity_type)) {
    sql <- paste0(sql, " AND e.entity_type = ?")
    params <- c(params, list(entity_type))
  }
  sql <- paste0(sql, "
     GROUP BY e.entity_value
     HAVING witness_count >= ?
     ORDER BY witness_count DESC, total_mentions DESC
     LIMIT ?")
  params <- c(params, list(min_witnesses, limit))
  as.data.frame(dbGetQuery(conn, sql, params = params))
}

get_witness_mentions_for <- function(conn, entity_values) {
  if (length(entity_values) == 0) return(NULL)
  as.data.frame(dbGetQuery(conn, paste0(
    "SELECT e.entity_value, e.entity_type, s.canonical_name AS witness, e.context_text
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     WHERE s.role IN ('witness', 'witness_protected')
       AND e.entity_value IN (", paste(rep("?", length(entity_values)), collapse = ","), ")"),
    params = as.list(entity_values)))
}

find_contradictions <- function(conn, min_witnesses = 2, entity_type = NULL, limit = 200) {
  cands <- get_contradiction_candidates(conn, min_witnesses, entity_type, limit)
  if (nrow(cands) == 0) return(detect_contradictions(NULL))
  mentions <- get_witness_mentions_for(conn, cands$entity_value)
  # Keep the type/witness counts from the candidate query
  res <- detect_contradictions(mentions)
  res$entity_type <- cands$entity_type[match(res$entity_value, cands$entity_value)]
  res
}

get_entity_by_witness <- function(conn, entity_value) {
  df <- add_citations(as.data.frame(dbGetQuery(conn, paste0(
    "SELECT s.canonical_name AS witness, s.role,
            e.context_text, h.hearing_date, h.day_number, ",
    citation_columns_sql(conn, "entities", "e"), "
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     LEFT JOIN hearings h ON h.id = e.hearing_id
     WHERE LOWER(e.entity_value) = LOWER(?)
       AND s.role IN ('witness', 'witness_protected')
     ORDER BY s.canonical_name, h.day_number
     LIMIT 500"),
    params = list(entity_value)
  )))
  if (nrow(df) > 0) df$stance <- classify_stance(df$context_text)
  df
}

# ── Premium: Evidence Bundle Export ──────────────────────────────

generate_bundle_html <- function(conn, entity_value, entity_type) {
  mentions <- get_entity_mentions(conn, entity_value, limit = 500)
  if (is.null(mentions) || nrow(mentions) == 0) return(NULL)

  docs <- mentions[mentions$source_type != "transcript", , drop = FALSE]
  testimony <- mentions[mentions$source_type == "transcript", , drop = FALSE]

  total_witnesses <- length(unique(testimony$speaker))
  total_docs <- length(unique(docs$speaker))
  date_range <- ""
  if (nrow(mentions) > 0) {
    dates <- na.omit(as.Date(mentions$hearing_date))
    if (length(dates) > 0) date_range <- paste(min(dates), "to", max(dates))
  }

    rows_html <- ""
  if (nrow(testimony) > 0) {
    for (i in seq_len(nrow(testimony))) {
      r <- testimony[i, ]
      rows_html <- paste0(rows_html, '
        <tr>
          <td class="date">', r$hearing_date %||% "", '</td>
          <td class="witness">', escape_html(r$speaker %||% ""), '</td>
          <td class="context">', escape_html(substr(r$context_text %||% "", 1, 300)), '</td>
          <td class="cite">', escape_html(r$citation %||% ""), '</td>
        </tr>')
    }
  }

  doc_rows <- ""
  if (nrow(docs) > 0) {
    for (i in seq_len(nrow(docs))) {
      r <- docs[i, ]
      doc_rows <- paste0(doc_rows, '
        <tr>
          <td class="date">', r$hearing_date %||% "", '</td>
          <td class="witness">', escape_html(r$speaker %||% ""), '</td>
          <td class="context">', escape_html(substr(r$context_text %||% "", 1, 300)), '</td>
          <td class="type">', r$source_type %||% "", '</td>
        </tr>')
    }
  }

  html <- paste0('
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Evidence Bundle — ', escape_html(entity_value), '</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: "Inter", "Segoe UI", Arial, sans-serif; background: #fff; color: #222; padding: 40px; }
  h1 { font-size: 1.8rem; border-bottom: 3px solid #1a3a5c; padding-bottom: 8px; margin-bottom: 20px; }
  .meta { display: flex; gap: 24px; margin-bottom: 30px; flex-wrap: wrap; }
  .meta-item { background: #f5f7fa; padding: 12px 20px; border-radius: 8px; }
  .meta-item strong { display: block; font-size: 0.7rem; text-transform: uppercase; color: #666; }
  .meta-item span { font-size: 1.3rem; font-weight: 700; color: #1a3a5c; }
  h2 { font-size: 1.2rem; margin: 24px 0 12px; color: #1a3a5c; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 30px; font-size: 0.85rem; }
  th { background: #1a3a5c; color: #fff; padding: 10px 12px; text-align: left; }
  td { padding: 8px 12px; border-bottom: 1px solid #e0e0e0; vertical-align: top; }
  tr:hover { background: #f0f4ff; }
  .date { white-space: nowrap; width: 100px; }
  .witness { white-space: nowrap; width: 160px; }
  .cite { white-space: nowrap; width: 170px; color: #444; font-size: 0.8rem; }
  .actions { margin-bottom: 20px; }
  .actions button { background: #1a3a5c; color: #fff; border: 0; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-size: 0.85rem; }
  .type { width: 80px; color: #666; text-transform: capitalize; }
  .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 0.75rem; color: #999; }
  .footer .disclaimer { color: #555; font-size: 0.8rem; margin-bottom: 8px; }
  @media print { body { padding: 20px; } .actions { display: none; } th { background: #1a3a5c !important; color: #fff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
</style>
</head>
<body>
  <h1>Evidence Bundle: ', escape_html(entity_value), '</h1>
  <p style="color:#666;margin-bottom:20px;">', escape_html(entity_type %||% ""), ' &mdash; Generated ', Sys.Date(), '</p>
  <div class="actions"><button onclick="window.print()">Print / Save as PDF</button></div>
  <div class="meta">
    <div class="meta-item"><strong>Witnesses</strong><span>', total_witnesses, '</span></div>
    <div class="meta-item"><strong>Statements</strong><span>', total_docs, '</span></div>
    <div class="meta-item"><strong>Total Mentions</strong><span>', nrow(mentions), '</span></div>
    <div class="meta-item"><strong>Date Range</strong><span>', date_range, '</span></div>
  </div>

  <h2>Witness Testimony (', nrow(testimony), ' mentions)</h2>
  <table>
    <thead><tr><th>Date</th><th>Witness</th><th>Context</th><th>Citation</th></tr></thead>
    <tbody>', rows_html, '</tbody>
  </table>

  <h2>Witness Statements (', nrow(docs), ' mentions)</h2>
  <table>
    <thead><tr><th>Date</th><th>Source</th><th>Context</th><th>Type</th></tr></thead>
    <tbody>', doc_rows, '</tbody>
  </table>

  <div class="footer">
    <p class="disclaimer">', escape_html(INQUIRY$disclaimer), '</p>',
    escape_html(INQUIRY$branding$product_name), ' &mdash; ', escape_html(INQUIRY$short_name),
    ' &mdash; Confidential',
    '<br>Generated ', format(Sys.time(), "%Y-%m-%d %H:%M"), '
  </div>
</body>
</html>')

  html
}

# ── Institutional analysis ───────────────────────────────────────
# Read-only access to institutional_analysis.db (pipeline/build_institutional_db.py).

get_institutional_db <- function(candidates = INSTITUTIONAL_DB_CANDIDATES) {
  path <- Filter(file.exists, candidates)
  if (length(path) == 0) return(NULL)
  dbConnect(SQLite(), path[[1]], flags = SQLITE_RO)
}

get_institutions <- function(con) {
  as.data.frame(dbGetQuery(con,
    "SELECT i.id, i.department, i.abbreviation, i.jurisdiction, i.budget, i.notes,
            p.abbreviation AS parent, g.abbreviation AS governed_by,
            (SELECT COUNT(*) FROM positions WHERE institution_id = i.id) +
            (SELECT COUNT(*) FROM audit_outcomes WHERE institution_id = i.id) +
            (SELECT COUNT(*) FROM allegations WHERE target_institution_id = i.id) +
            (SELECT COUNT(*) FROM witness_topics WHERE institution_id = i.id) AS records
     FROM institutions i
     LEFT JOIN institutions p ON p.id = i.parent_id
     LEFT JOIN institutions g ON g.id = i.governing_institution_id
     ORDER BY records DESC, i.id"))
}

get_institution_positions <- function(con, institution_id) {
  as.data.frame(dbGetQuery(con,
    "SELECT p.full_name, pos.title, pos.start_date, pos.end_date,
            pos.is_accounting_officer, pos.is_cfo, pos.appointed_by, pos.source, pos.notes
     FROM positions pos
     JOIN people p ON p.id = pos.person_id
     WHERE pos.institution_id = ?
     ORDER BY pos.start_date",
    params = list(institution_id)))
}

get_institution_audits <- function(con, institution_id) {
  as.data.frame(dbGetQuery(con,
    "SELECT financial_year, audit_opinion, material_irregularities,
            irregular_expenditure_details, supply_chain_findings, source
     FROM audit_outcomes WHERE institution_id = ?
     ORDER BY financial_year",
    params = list(institution_id)))
}

get_institution_allegations <- function(con, institution_id) {
  as.data.frame(dbGetQuery(con,
    "SELECT w.full_name AS witness, t.full_name AS target_person, a.category,
            a.severity, a.summary, a.day_number, a.context_snippet, a.corroborated_by
     FROM allegations a
     JOIN people w ON w.id = a.witness_id
     LEFT JOIN people t ON t.id = a.target_person_id
     WHERE a.target_institution_id = ?
     ORDER BY a.day_number",
    params = list(institution_id)))
}

get_institution_conflicts <- function(con, institution_id) {
  as.data.frame(dbGetQuery(con,
    "SELECT c.title, c.category, c.severity, c.detail, c.source,
            i1.abbreviation AS primary_inst, i2.abbreviation AS secondary_inst
     FROM conflicts_of_interest c
     LEFT JOIN institutions i1 ON i1.id = c.institution_primary_id
     LEFT JOIN institutions i2 ON i2.id = c.institution_secondary_id
     WHERE c.institution_primary_id = ? OR c.institution_secondary_id = ?
     ORDER BY CASE c.severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2
                              WHEN 'medium' THEN 3 ELSE 4 END",
    params = list(institution_id, institution_id)))
}

get_institution_witness_topics <- function(con, institution_id) {
  as.data.frame(dbGetQuery(con,
    "SELECT p.full_name AS witness, wt.day_numbers, wt.key_topics, wt.sentiment
     FROM witness_topics wt
     JOIN people p ON p.id = wt.witness_id
     WHERE wt.institution_id = ?",
    params = list(institution_id)))
}

# Financial years the institutional research is meant to cover
# (research/Institutional_Failure_Methodology.md)
RESEARCH_YEARS <- c("2020/21", "2021/22", "2022/23", "2023/24", "2024/25")

# What is still missing for one institution, as a character vector.
get_research_gaps <- function(con, institution_id, years = RESEARCH_YEARS) {
  inst <- dbGetQuery(con, "SELECT budget FROM institutions WHERE id = ?",
                     params = list(institution_id))
  gaps <- character(0)
  if (nrow(inst) == 0) return(gaps)
  if (is.na(inst$budget[1])) gaps <- c(gaps, "Budget not recorded")

  audits <- get_institution_audits(con, institution_id)
  missing_years <- setdiff(years, audits$financial_year)
  if (length(missing_years) > 0)
    gaps <- c(gaps, paste0("No AGSA audit outcome for ", paste(missing_years, collapse = ", ")))

  pos <- get_institution_positions(con, institution_id)
  if (nrow(pos) == 0) {
    gaps <- c(gaps, "No leadership positions recorded")
  } else {
    approx <- pos$full_name[grepl("~", paste(pos$start_date, pos$end_date))]
    if (length(approx) > 0)
      gaps <- c(gaps, paste0("Approximate tenure dates: ", paste(unique(approx), collapse = ", ")))
    if (!any(pos$is_accounting_officer == 1))
      gaps <- c(gaps, "No accounting officer recorded")
  }

  unconfirmed <- dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM cross_institutional_moves
     WHERE (from_institution_id = ? OR to_institution_id = ?)
       AND (source LIKE '%inference%' OR source LIKE '%confirm%')",
    params = list(institution_id, institution_id))$n
  if (unconfirmed > 0)
    gaps <- c(gaps, paste0(unconfirmed, " career move(s) still need source confirmation"))
  gaps
}

# ── Annotations (shared notes and flags) ─────────────────────────
# kind: "note" (research note) or "flag" (evidence leader says the
# extracted data is wrong against the source).

get_annotations_db <- function(path = ANNOTATIONS_DB_PATH) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- dbConnect(SQLite(), path)
  dbExecute(con, "PRAGMA busy_timeout = 5000")
  dbExecute(con, "PRAGMA journal_mode = WAL")
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS annotations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL,
      author TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'note' CHECK(kind IN ('note', 'flag')),
      source TEXT NOT NULL,
      source_id INTEGER,
      citation TEXT DEFAULT '',
      speaker TEXT DEFAULT '',
      excerpt TEXT DEFAULT '',
      note TEXT NOT NULL
    )")
  con
}

add_annotation <- function(con, author, kind, source, source_id, citation,
                           speaker, excerpt, note) {
  author <- trimws(author %||% "")
  note <- trimws(note %||% "")
  if (!nzchar(author)) stop("Enter your name before saving a note.")
  if (!nzchar(note)) stop("The note is empty.")
  if (!kind %in% c("note", "flag")) stop("Unknown note type.")
  dbExecute(con,
    "INSERT INTO annotations (created_at, author, kind, source, source_id,
                              citation, speaker, excerpt, note)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), author, kind,
                  source %||% "", as.integer(source_id %||% NA), citation %||% "",
                  speaker %||% "", substr(excerpt %||% "", 1, 1000), note))
  invisible(TRUE)
}

get_annotations <- function(con, kind = NULL, source = NULL, source_id = NULL) {
  sql <- "SELECT id, created_at, author, kind, source, source_id, citation,
                 speaker, excerpt, note FROM annotations WHERE 1 = 1"
  params <- list()
  if (!is.null(kind)) { sql <- paste0(sql, " AND kind = ?"); params <- c(params, list(kind)) }
  if (!is.null(source)) { sql <- paste0(sql, " AND source = ?"); params <- c(params, list(source)) }
  if (!is.null(source_id)) {
    sql <- paste0(sql, " AND source_id = ?"); params <- c(params, list(as.integer(source_id)))
  }
  sql <- paste0(sql, " ORDER BY id DESC")
  as.data.frame(if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql))
}

# Authors can delete only their own notes.
delete_annotation <- function(con, id, author) {
  dbExecute(con, "DELETE FROM annotations WHERE id = ? AND author = ?",
            params = list(as.integer(id), author)) > 0
}

annotations_version <- function(con) {
  dbGetQuery(con, "SELECT COUNT(*) AS n, COALESCE(MAX(id), 0) AS max_id FROM annotations")
}
