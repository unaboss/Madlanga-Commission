# global.R — Commission Research Tool — Shared logic
library(DBI)
library(RSQLite)
library(dplyr)
library(lubridate)
library(stringr)
library(jsonlite)

# ── License check ────────────────────────────────────────────────
source("license_check.r")
LICENSE <- validate_license()

if (LICENSE$status == "expired") {
  stop(LICENSE$message)
}

# ── Paths ───────────────────────────────────────────────────────
APP_DIR  <- getwd()
DB_PATH <- normalizePath(file.path(APP_DIR, "data", "commission_research.db"), mustWork = FALSE)
NETWORK_PATH   <- file.path(APP_DIR, "www", "network_data.json")
ATTENTION_PATH <- file.path(APP_DIR, "www", "attention_matrix.json")
STORYMAP_PATH  <- file.path(APP_DIR, "www", "story_map_data.json")

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

# ── DB Connection ───────────────────────────────────────────────
get_db <- function() {
  if (!file.exists(DB_PATH)) stop("Database not found at: ", DB_PATH)
  dbConnect(SQLite(), DB_PATH)
}

# ── Load network data ───────────────────────────────────────────
network_cache <- NULL
load_network <- function() {
  if (is.null(network_cache)) {
    network_cache <<- fromJSON(NETWORK_PATH, simplifyDataFrame = FALSE)
  }
  network_cache
}

attention_cache <- NULL
load_attention <- function() {
  if (is.null(attention_cache)) {
    attention_cache <<- fromJSON(ATTENTION_PATH, simplifyVector = TRUE)
  }
  attention_cache
}

storymap_cache <- NULL
load_story_map <- function() {
  if (is.null(storymap_cache)) {
    if (file.exists(STORYMAP_PATH)) {
      storymap_cache <<- fromJSON(STORYMAP_PATH, simplifyDataFrame = FALSE)
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
    "SELECT source, title, date, speaker, ",
    "snippet(search_index, 3, '<mark>', '</mark>', '...', 45) AS snippet, ",
    "substr(text, 1, 400) AS preview ",
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
  as.data.frame(dbGetQuery(conn, sql, params = params))
}

get_hearings <- function(conn) {
  as.data.frame(dbGetQuery(conn,
    "SELECT day_number, hearing_date, summary FROM hearings ORDER BY day_number"))
}

get_witness_segments <- function(conn, speaker_name) {
  as.data.frame(dbGetQuery(conn,
    "SELECT h.day_number, h.hearing_date, ts.text, ts.page_number
     FROM transcript_segments ts
     JOIN speakers s ON s.id = ts.speaker_id
     JOIN hearings h ON h.id = ts.hearing_id
     WHERE s.canonical_name LIKE ?
     ORDER BY h.day_number, ts.id
     LIMIT 500",
    params = list(paste0("%", speaker_name, "%"))
  ))
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
  as.data.frame(dbGetQuery(conn,
    "SELECT e.id, e.entity_type, e.entity_value, e.context_text,
            h.hearing_date, h.day_number,
            s.canonical_name AS speaker, s.role AS speaker_role,
            e.source AS source_type
     FROM entities e
     LEFT JOIN hearings h ON h.id = e.hearing_id
     LEFT JOIN speakers s ON s.id = e.speaker_id
     WHERE LOWER(e.entity_value) = LOWER(?)
     ORDER BY h.hearing_date
     LIMIT ?",
    params = list(entity_value, limit)
  ))
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

get_contradiction_candidates <- function(conn, min_witnesses = 2, limit = 50) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.entity_value, e.entity_type,
            COUNT(DISTINCT e.speaker_id) AS witness_count,
            COUNT(*) AS total_mentions
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     WHERE s.role IN ('witness', 'witness_protected')
     GROUP BY e.entity_value
     HAVING witness_count >= ?
     ORDER BY witness_count DESC, total_mentions DESC
     LIMIT ?",
    params = list(min_witnesses, limit)
  ))
}

get_entity_by_witness <- function(conn, entity_value) {
  as.data.frame(dbGetQuery(conn,
    "SELECT s.canonical_name AS witness, s.role,
            e.context_text, h.hearing_date, h.day_number
     FROM entities e
     JOIN speakers s ON s.id = e.speaker_id
     LEFT JOIN hearings h ON h.id = e.hearing_id
     WHERE LOWER(e.entity_value) = LOWER(?)
       AND s.role IN ('witness', 'witness_protected')
     ORDER BY s.canonical_name, h.day_number
     LIMIT 500",
    params = list(entity_value)
  ))
}

# ── Premium: Evidence Bundle Export ──────────────────────────────

generate_bundle_html <- function(conn, entity_value, entity_type) {
  mentions <- get_entity_mentions(conn, entity_value, limit = 500)
  if (is.null(mentions) || nrow(mentions) == 0) return(NULL)

  docs <- mentions[mentions$source_type != "transcript", , drop = FALSE]
  testimony <- mentions[mentions$source_type == "transcript", , drop = FALSE]

  total_witnesses <- length(unique(testimony$speaker))
  total_docs <- length(unique(docs$source))
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
          <td class="day">Day ', r$day_number %||% "", '</td>
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
  .day { white-space: nowrap; width: 60px; color: #666; }
  .type { width: 80px; color: #666; text-transform: capitalize; }
  .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 0.75rem; color: #999; }
  @media print { body { padding: 20px; } th { background: #1a3a5c !important; color: #fff !important; } }
</style>
</head>
<body>
  <h1>Evidence Bundle: ', escape_html(entity_value), '</h1>
  <p style="color:#666;margin-bottom:20px;">', escape_html(entity_type %||% ""), ' &mdash; Generated ', Sys.Date(), '</p>
  <div class="meta">
    <div class="meta-item"><strong>Witnesses</strong><span>', total_witnesses, '</span></div>
    <div class="meta-item"><strong>Documents</strong><span>', total_docs, '</span></div>
    <div class="meta-item"><strong>Total Mentions</strong><span>', nrow(mentions), '</span></div>
    <div class="meta-item"><strong>Date Range</strong><span>', date_range, '</span></div>
  </div>

  <h2>Witness Testimony (', nrow(testimony), ' mentions)</h2>
  <table>
    <thead><tr><th>Date</th><th>Witness</th><th>Context</th><th>Day</th></tr></thead>
    <tbody>', rows_html, '</tbody>
  </table>

  <h2>Commission Documents (', nrow(docs), ' mentions)</h2>
  <table>
    <thead><tr><th>Date</th><th>Source</th><th>Context</th><th>Type</th></tr></thead>
    <tbody>', doc_rows, '</tbody>
  </table>

  <div class="footer">
    Commission Research Intelligence Dashboard &mdash; Confidential',
    '<br>Generated ', format(Sys.time(), "%Y-%m-%d %H:%M"), '
  </div>
</body>
</html>')

  html
}
