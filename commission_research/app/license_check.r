# license_check.r — License validation for Commission Research Dashboard
library(digest)
library(jsonlite)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

LICENSE_FILE <- normalizePath(file.path(getwd(), "license.key"), mustWork = FALSE)

# ── CONFIGURATION ─────────────────────────────────────────────────────
# License checks are ON by default. Set MADLANGA_DEV_MODE=true (env var or
# .Renviron) to skip them while prototyping locally. Never set it on a
# customer deployment.
DEV_MODE <- tolower(Sys.getenv("MADLANGA_DEV_MODE", unset = "false")) %in% c("1", "true", "yes")

# Secret key for HMAC signatures (MUST match tools/generate_license.py).
# Read from env var, else from a gitignored .license_secret file in the app
# directory or the project root. Returns "" when it is not configured.
load_license_secret <- function() {
  env_secret <- Sys.getenv("MADLANGA_LICENSE_SECRET", unset = "")
  if (nzchar(env_secret)) {
    return(env_secret)
  }
  candidates <- c(
    file.path(getwd(), ".license_secret"),
    file.path(getwd(), "..", ".license_secret"),
    file.path(getwd(), "..", "..", ".license_secret")
  )
  for (p in candidates) {
    if (file.exists(p)) {
      return(trimws(readLines(p, n = 1, warn = FALSE)))
    }
  }
  ""
}

# Grace period in days after expiry before hard block
GRACE_DAYS <- 14

# Optional online validation server (tools/license_server.py), e.g.
# https://licenses.example.com/api/check-license. Empty disables it.
VALIDATION_URL <- Sys.getenv("MADLANGA_LICENSE_URL", unset = "")

# Statuses that block access to the dashboard
BLOCKING_STATUSES <- c("expired", "invalid", "revoked")
# ─────────────────────────────────────────────────────────────────────

license_blocks_access <- function(lic) {
  isTRUE(lic$status %in% BLOCKING_STATUSES)
}

license_signature <- function(secret, customer, tier, expiry, issued) {
  hmac(key = secret, object = paste(customer, tier, expiry, issued, sep = "|"),
       algo = "sha256")
}

validate_license <- function(license_file = LICENSE_FILE,
                             secret = load_license_secret(),
                             dev_mode = DEV_MODE,
                             validation_url = VALIDATION_URL,
                             today = Sys.Date()) {
  if (isTRUE(dev_mode)) {
    return(list(
      status = "valid",
      message = "Development mode — license check skipped",
      customer = "Development",
      tier = "enterprise",
      expiry = NULL,
      days_left = 365,
      grace_left = GRACE_DAYS
    ))
  }

  # Anything that fails below leaves the dashboard locked on the lowest tier
  result <- list(
    status = "invalid",
    message = "",
    customer = "",
    tier = "starter",
    expiry = NULL,
    days_left = 0,
    grace_left = 0
  )

  if (!nzchar(secret)) {
    result$message <- "License secret is not configured on this server."
    return(result)
  }

  if (!file.exists(license_file)) {
    result$message <- "License file not found. Please activate your license."
    return(result)
  }

  lic <- tryCatch(fromJSON(license_file), error = function(e) NULL)
  if (is.null(lic) || is.null(lic$expiry) || is.null(lic$sig)) {
    result$message <- "Invalid license file."
    return(result)
  }

  lic$tier <- lic$tier %||% "starter"
  if (!lic$tier %in% c("starter", "professional", "enterprise")) {
    lic$tier <- "starter"
  }

  expected <- license_signature(secret, lic$customer, lic$tier, lic$expiry,
                                lic$issued %||% lic$expiry)
  if (!identical(lic$sig, expected)) {
    result$message <- "License signature invalid."
    return(result)
  }

  result$customer <- lic$customer
  result$tier <- lic$tier
  result$expiry <- as.Date(lic$expiry)
  days_left <- as.numeric(result$expiry - as.Date(today))
  result$days_left <- days_left

  if (days_left >= 0) {
    result$status <- "valid"
    result$grace_left <- GRACE_DAYS
    result$message <- paste0("License valid until ", result$expiry,
      " (", days_left, " days remaining)")
  } else if (days_left >= -GRACE_DAYS) {
    result$status <- "grace_period"
    result$grace_left <- GRACE_DAYS + days_left
    result$message <- paste0("License expired ", abs(days_left),
      " days ago. Renew within ", result$grace_left, " days.")
  } else {
    result$status <- "expired"
    result$grace_left <- 0
    result$message <- "License expired. Contact your provider to renew."
  }

  # Online revocation check. A network failure never blocks the dashboard;
  # only an explicit 403 from the license server does.
  if (nzchar(validation_url) && !license_blocks_access(result)) {
    tryCatch({
      resp <- httr::GET(validation_url, query = list(
        key = lic$sig,
        customer = lic$customer
      ), httr::timeout(3))
      if (httr::status_code(resp) == 403) {
        result$status <- "revoked"
        result$message <- "License revoked. Please contact support."
      }
    }, error = function(e) {})
  }

  result
}
