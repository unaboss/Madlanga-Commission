# Load the app's shared logic (global.R) without starting the app.
app_dir <- normalizePath(file.path(testthat::test_path(), "..", "..", "app"))
local({
  old <- setwd(app_dir)
  on.exit(setwd(old))
  suppressPackageStartupMessages(sys.source("global.R", envir = globalenv()))
})
