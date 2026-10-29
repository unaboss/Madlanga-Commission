test_that("stance classification favours denial when both appear", {
  expect_equal(classify_stance(c(
    "I deny that. Crime Intelligence never received any money.",
    "Yes, I confirm the money was paid.",
    "The hearing adjourned at four.",
    NA
  )), c("denies", "affirms", "neutral", "neutral"))
})

mentions <- data.frame(
  entity_value = c("Carnilinx", "Carnilinx", "Carnilinx", "Task Team", "Task Team"),
  entity_type = c("organization", "organization", "organization", "organization", "organization"),
  witness = c("Witness A", "Witness B", "Witness C", "Witness A", "Witness B"),
  context_text = c("I confirm Carnilinx paid him.", "That is not true, Carnilinx never paid.",
                   "I saw Carnilinx officials there.", "The Task Team met weekly.",
                   "The Task Team was formed in 2022."),
  stringsAsFactors = FALSE
)

test_that("entities with opposing witnesses are flagged and ranked first", {
  res <- detect_contradictions(mentions)
  expect_equal(res$entity_value, c("Carnilinx", "Task Team"))
  expect_equal(res$conflict_pairs, c(2L, 0L))
  expect_equal(res$affirming[1], "Witness A, Witness C")
  expect_equal(res$denying[1], "Witness B")
  expect_equal(rownames(res), c("1", "2"))
})

test_that("a witness contradicting only themselves is not a cross-witness conflict", {
  self <- mentions[c(1, 1), ]
  self$context_text <- c("I confirm it.", "I deny it.")
  expect_equal(detect_contradictions(self)$conflict_pairs, 0L)
})

test_that("no mentions gives an empty result", {
  expect_equal(nrow(detect_contradictions(NULL)), 0)
})

test_that("the entity type filter is applied in the database query", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "CREATE TABLE speakers (id INTEGER, canonical_name TEXT, role TEXT)")
  DBI::dbExecute(con, "CREATE TABLE entities (id INTEGER, entity_type TEXT, entity_value TEXT,
                      context_text TEXT, speaker_id INTEGER)")
  DBI::dbExecute(con, "INSERT INTO speakers VALUES (1, 'A', 'witness'), (2, 'B', 'witness')")
  DBI::dbExecute(con, "INSERT INTO entities VALUES
    (1, 'organization', 'SAPS', 'I confirm SAPS paid', 1),
    (2, 'organization', 'SAPS', 'SAPS never paid', 2),
    (3, 'location', 'Pretoria', 'I confirm Pretoria', 1),
    (4, 'location', 'Pretoria', 'I deny Pretoria', 2)")
  expect_setequal(find_contradictions(con)$entity_value, c("SAPS", "Pretoria"))
  only_loc <- find_contradictions(con, entity_type = "location")
  expect_equal(only_loc$entity_value, "Pretoria")
  expect_equal(only_loc$conflict_pairs, 1L)
})
