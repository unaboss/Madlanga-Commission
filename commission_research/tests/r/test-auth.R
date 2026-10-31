new_auth_db <- function() auth_db(file.path(withr::local_tempdir(.local_envir = parent.frame()), "users.db"))

test_that("users sign in with the right password only, and the message doesn't reveal accounts", {
  con <- new_auth_db()
  on.exit(DBI::dbDisconnect(con))
  create_user(con, "thandi", "long-enough-pw", "analyst", "Thandi M")

  ok <- attempt_login(con, "Thandi", "long-enough-pw")
  expect_true(ok$ok)
  expect_equal(ok$user$username, "thandi")
  expect_equal(ok$user$role, "analyst")

  wrong <- attempt_login(con, "thandi", "nope-nope-nope")
  nobody <- attempt_login(con, "ghost", "whatever-long")
  expect_false(wrong$ok)
  expect_identical(wrong$message, nobody$message)
})

test_that("passwords are hashed, and weak passwords or bad roles are refused", {
  con <- new_auth_db()
  on.exit(DBI::dbDisconnect(con))
  create_user(con, "sipho", "long-enough-pw")
  stored <- DBI::dbGetQuery(con, "SELECT password_hash FROM users")$password_hash
  expect_false(grepl("long-enough-pw", stored, fixed = TRUE))
  expect_error(create_user(con, "a1", "short"), "at least")
  expect_error(create_user(con, "a2", "long-enough-pw", role = "owner"), "Role")
  expect_error(create_user(con, "SIPHO", "long-enough-pw"), "already exists")
  expect_error(create_user(con, "bad name!", "long-enough-pw"), "Usernames")
})

test_that("sessions resolve to the user, expire, and end on logout, password change or disable", {
  con <- new_auth_db()
  on.exit(DBI::dbDisconnect(con))
  create_user(con, "lerato", "long-enough-pw", "viewer")

  token <- issue_session(con, "lerato")
  expect_equal(session_user(con, token)$role, "viewer")
  expect_null(session_user(con, "forged-token"))
  expect_false(token %in% DBI::dbGetQuery(con, "SELECT token_hash FROM sessions")$token_hash)

  end_session(con, token)
  expect_null(session_user(con, token))

  t2 <- issue_session(con, "lerato")
  set_password(con, "lerato", "another-long-pw")
  expect_null(session_user(con, t2))

  t3 <- issue_session(con, "lerato")
  set_disabled(con, "lerato", TRUE)
  expect_null(session_user(con, t3))
  expect_false(attempt_login(con, "lerato", "another-long-pw")$ok)

  expired <- issue_session(con, "lerato", hours = -1)
  set_disabled(con, "lerato", FALSE)
  expect_null(session_user(con, expired))
})

test_that("repeated failures lock the account for a while", {
  con <- new_auth_db()
  on.exit(DBI::dbDisconnect(con))
  create_user(con, "zanele", "long-enough-pw")
  for (i in seq_len(MAX_FAILED_LOGINS)) attempt_login(con, "zanele", "wrong-password")
  locked <- attempt_login(con, "zanele", "long-enough-pw")
  expect_false(locked$ok)
  expect_match(locked$message, "Too many")
})

test_that("cookies are read from the request header", {
  expect_equal(read_cookie("a=1; cr_session=abc%20def; b=2"), "abc def")
  expect_null(read_cookie("a=1"))
  expect_null(read_cookie(NULL))
})

test_that("logins are on by default and off in dev mode or when switched off", {
  expect_true(auth_enabled(setting = "on", dev_mode = FALSE))
  expect_false(auth_enabled(setting = "off", dev_mode = FALSE))
  expect_false(auth_enabled(setting = "on", dev_mode = TRUE))
})

test_that("viewers can't write notes; analysts and admins can", {
  as_session <- function(role) {
    s <- new.env()
    s$userData <- new.env()
    s$userData$auth_user <- list(username = "u", display_name = "U", role = role)
    s
  }
  expect_false(can_write_notes(as_session("viewer")))
  expect_true(can_write_notes(as_session("analyst")))
  expect_true(can_write_notes(as_session("admin")))
})
