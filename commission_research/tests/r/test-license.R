write_license <- function(dir, customer = "Acme Legal", tier = "professional",
                          expiry = "2026-12-31", issued = "2026-10-01",
                          secret = "s3cret", sig = NULL) {
  path <- file.path(dir, "license.key")
  sig <- sig %||% license_signature(secret, customer, tier, expiry, issued)
  jsonlite::write_json(list(customer = customer, tier = tier, expiry = expiry,
                            issued = issued, sig = sig), path, auto_unbox = TRUE)
  path
}

check <- function(path, ...) {
  validate_license(license_file = path, secret = "s3cret", dev_mode = FALSE,
                   validation_url = "", today = as.Date("2026-10-29"), ...)
}

test_that("a correctly signed license is valid with its tier", {
  lic <- check(write_license(withr::local_tempdir()))
  expect_equal(lic$status, "valid")
  expect_equal(lic$tier, "professional")
  expect_false(license_blocks_access(lic))
})

test_that("missing, tampered and unsigned licenses block access on the starter tier", {
  dir <- withr::local_tempdir()
  missing <- check(file.path(dir, "nope.key"))
  expect_equal(missing$status, "invalid")
  expect_true(license_blocks_access(missing))

  tampered <- check(write_license(dir, sig = "deadbeef"))
  expect_equal(tampered$status, "invalid")
  expect_equal(tampered$tier, "starter")

  upgraded <- write_license(dir)
  lic <- jsonlite::read_json(upgraded)
  lic$tier <- "enterprise"
  jsonlite::write_json(lic, upgraded, auto_unbox = TRUE)
  expect_equal(check(upgraded)$status, "invalid")
})

test_that("no secret on the server blocks access instead of crashing", {
  path <- write_license(withr::local_tempdir())
  lic <- validate_license(license_file = path, secret = "", dev_mode = FALSE,
                          validation_url = "")
  expect_equal(lic$status, "invalid")
  expect_match(lic$message, "secret")
})

test_that("expiry has a grace period before the hard block", {
  dir <- withr::local_tempdir()
  grace <- check(write_license(dir, expiry = "2026-10-20"))
  expect_equal(grace$status, "grace_period")
  expect_false(license_blocks_access(grace))
  expired <- check(write_license(dir, expiry = "2026-09-01"))
  expect_equal(expired$status, "expired")
  expect_true(license_blocks_access(expired))
})

test_that("dev mode is off unless MADLANGA_DEV_MODE is set", {
  withr::local_envvar(MADLANGA_DEV_MODE = NA)
  expect_false(tolower(Sys.getenv("MADLANGA_DEV_MODE", "false")) %in% c("1", "true", "yes"))
  dev <- validate_license(license_file = "nope", secret = "", dev_mode = TRUE)
  expect_equal(dev$status, "valid")
})

test_that("an unreachable license server does not lock customers out", {
  lic <- validate_license(license_file = write_license(withr::local_tempdir()),
                          secret = "s3cret", dev_mode = FALSE,
                          validation_url = "http://127.0.0.1:9/api/check-license",
                          today = as.Date("2026-10-29"))
  expect_equal(lic$status, "valid")
})
