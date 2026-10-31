#!/usr/bin/env Rscript
# manage_users.R — Manage dashboard logins from the command line.
#
# Run from the repository root:
#   Rscript tools/manage_users.R add <username> [--role admin|analyst|viewer] [--name "Full Name"]
#   Rscript tools/manage_users.R password <username>
#   Rscript tools/manage_users.R role <username> <admin|analyst|viewer>
#   Rscript tools/manage_users.R disable <username>
#   Rscript tools/manage_users.R enable <username>
#   Rscript tools/manage_users.R list
#
# Passwords are read from the MADLANGA_NEW_PASSWORD env var if set, else
# prompted for. The users database is MADLANGA_USERS_DB, default
# commission_research/app/data/users.db (ship it with the app, or point the
# env var at persistent storage).

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

args <- commandArgs(trailingOnly = TRUE)
script_dir <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
app_dir <- normalizePath(file.path(script_dir, "..", "commission_research", "app"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
DEV_MODE <- FALSE
INQUIRY <- list(branding = list(product_name = ""), short_name = "", contact = list())
old <- setwd(app_dir)
source("auth.R")
setwd(old)

usage <- function() {
  cat(readLines(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))[3:10],
      sep = "\n")
  quit(status = 1)
}

opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}

read_password <- function(username) {
  pw <- Sys.getenv("MADLANGA_NEW_PASSWORD", unset = "")
  if (nzchar(pw)) return(pw)
  if (!interactive() && !isatty(stdin())) stop("Set MADLANGA_NEW_PASSWORD or run in a terminal.")
  cat("Password for ", username, " (", MIN_PASSWORD_CHARS, "+ characters): ", sep = "")
  system("stty -echo", ignore.stderr = TRUE)
  pw <- readLines(file("stdin"), n = 1)
  system("stty echo", ignore.stderr = TRUE)
  cat("\n")
  pw
}

if (length(args) == 0) usage()
cmd <- args[1]
con <- auth_db()
on.exit(dbDisconnect(con))

result <- tryCatch({
  switch(cmd,
    add = {
      user <- args[2]
      create_user(con, user, read_password(user), opt("--role", "analyst"), opt("--name"))
      cat("Added ", user, " (", opt("--role", "analyst"), ") to ", AUTH_DB_PATH, "\n", sep = "")
    },
    password = {
      set_password(con, args[2], read_password(args[2]))
      cat("Password changed for ", args[2], "; their sessions were ended.\n", sep = "")
    },
    role = {
      set_role(con, args[2], args[3])
      cat(args[2], " is now ", args[3], ".\n", sep = "")
    },
    disable = { set_disabled(con, args[2], TRUE);  cat("Disabled ", args[2], ".\n", sep = "") },
    enable  = { set_disabled(con, args[2], FALSE); cat("Enabled ", args[2], ".\n", sep = "") },
    list = print(list_users(con), row.names = FALSE),
    usage()
  )
  0
}, error = function(e) {
  message("Error: ", conditionMessage(e))
  1
})
quit(status = result)
