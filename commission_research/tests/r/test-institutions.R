build_institution_db <- function() {
  path <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "inst.db")
  script <- normalizePath(file.path(app_dir, "..", "pipeline", "build_institutional_db.py"))
  # The build script writes next to the pipeline; run a copy that writes to `path`
  src <- readLines(script)
  src <- sub('^DB_PATH = .*$', paste0('DB_PATH = Path(r"', path, '")'), src)
  tmp <- tempfile(fileext = ".py")
  writeLines(src, tmp)
  out <- system2("python3", tmp, stdout = TRUE, stderr = TRUE)
  if (!file.exists(path)) stop(paste(out, collapse = "\n"))
  path
}

test_that("institution queries and research gaps read the seeded database", {
  skip_if(Sys.which("python3") == "", "python3 not available")
  con <- get_institutional_db(build_institution_db())
  on.exit(DBI::dbDisconnect(con))

  inst <- get_institutions(con)
  expect_equal(inst$abbreviation[1], "SAPS")  # most records first
  saps <- inst$id[inst$abbreviation == "SAPS"]

  expect_true("Lt Gen Nhlanhla Mkhwanazi" %in% get_institution_positions(con, saps)$full_name)
  expect_setequal(get_institution_audits(con, saps)$financial_year, c("2023/24", "2024/25"))

  gaps <- get_research_gaps(con, saps)
  expect_true(any(grepl("2020/21, 2021/22, 2022/23", gaps)))
  expect_false(any(grepl("Budget", gaps)))

  ministry <- inst$id[inst$abbreviation == "Police Ministry"]
  expect_true("No leadership positions recorded" %in% get_research_gaps(con, ministry))
})

test_that("a missing institutional database returns NULL", {
  expect_null(get_institutional_db(file.path(tempdir(), "does-not-exist.db")))
})
