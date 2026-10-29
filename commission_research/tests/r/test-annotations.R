test_that("notes and flags are shared, attributed and deletable only by their author", {
  con <- get_annotations_db(file.path(withr::local_tempdir(), "notes.db"))
  on.exit(DBI::dbDisconnect(con))

  add_annotation(con, "Thandi", "note", "transcript", 12, "Day 1, p.1, line 2",
                 "Adv Sello SC", "Thank you Chair.", "Follow up tomorrow")
  add_annotation(con, "Sipho", "flag", "entity", 40, "Day 2, p.1, lines 3–4",
                 "Lt Gen Khumalo", "I deny that.", "Speaker is wrong")

  all <- get_annotations(con)
  expect_equal(nrow(all), 2)
  expect_equal(get_annotations(con, kind = "flag")$note, "Speaker is wrong")
  expect_equal(get_annotations(con, source = "transcript", source_id = 12)$author, "Thandi")

  expect_false(delete_annotation(con, all$id[all$author == "Thandi"], "Sipho"))
  expect_true(delete_annotation(con, all$id[all$author == "Thandi"], "Thandi"))
  expect_equal(nrow(get_annotations(con)), 1)
})

test_that("notes need an author and text", {
  con <- get_annotations_db(file.path(withr::local_tempdir(), "notes.db"))
  on.exit(DBI::dbDisconnect(con))
  expect_error(add_annotation(con, "", "note", "transcript", 1, "", "", "", "x"), "name")
  expect_error(add_annotation(con, "A", "note", "transcript", 1, "", "", "", "  "), "empty")
})
