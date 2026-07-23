# global.R — Commission Research Tool — Shared logic
library(DBI)
library(RSQLite)
library(dplyr)
library(lubridate)
library(stringr)
library(jsonlite)

# ── Paths ───────────────────────────────────────────────────────
APP_DIR  <- getwd()
DB_PATH  <- normalizePath(file.path(APP_DIR, "..", "data", "commission_research.db"), mustWork = FALSE)
if (!file.exists(DB_PATH)) {
  DB_PATH <- normalizePath(file.path(APP_DIR, "data", "commission_research.db"), mustWork = FALSE)
}
NETWORK_PATH   <- file.path(APP_DIR, "www", "network_data.json")
STORYMAP_PATH  <- file.path(APP_DIR, "www", "story_map_data.json")

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
    "SELECT e.context_text, h.hearing_date, s.canonical_name AS speaker
     FROM entities e
     LEFT JOIN hearings h ON h.id = e.hearing_id
     LEFT JOIN speakers s ON s.id = e.speaker_id
     WHERE e.entity_value = ?
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
