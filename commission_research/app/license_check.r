# license_check.r — License validation for Commission Research Dashboard
library(digest)
library(jsonlite)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

LICENSE_FILE <- normalizePath(file.path(getwd(), "license.key"), mustWork = FALSE)

# ── CONFIGURATION ─────────────────────────────────────────────────────
# Set DEV_MODE = TRUE to skip license checks while prototyping
DEV_MODE <- TRUE

# Secret key for HMAC signatures (MUST match tools/generate_license.py).
# Read from env var, else from the gitignored .license_secret file at the project root.
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
  stop("License secret not configured. Set MADLANGA_LICENSE_SECRET or create .license_secret at the project root.")
}

SECRET_KEY <- load_license_secret()

# Grace period in days after expiry before hard block
GRACE_DAYS <- 14

# Optional online validation server (set to "" to disable)
VALIDATION_URL <- ""
# ─────────────────────────────────────────────────────────────────────

validate_license <- function() {
  result <- list(
    status = "valid",
    message = "Development mode — license check skipped",
    customer = "Development",
    tier = "enterprise",
    expiry = NULL,
    days_left = 365,
    grace_left = GRACE_DAYS
  )

  if (isTRUE(DEV_MODE)) {
    return(result)
  }

  if (!file.exists(LICENSE_FILE)) {
    result$status <- "invalid"
    result$message <- "License file not found. Please activate your license."
    return(result)
  }

  lic <- tryCatch(fromJSON(LICENSE_FILE), error = function(e) NULL)
  if (is.null(lic) || is.null(lic$expiry) || is.null(lic$sig)) {
    result$status <- "invalid"
    result$message <- "Invalid license file."
    return(result)
  }

  lic$tier <- lic$tier %||% "starter"
  if (!lic$tier %in% c("starter", "professional", "enterprise")) {
    lic$tier <- "starter"
  }

  expected <- hmac(
    key = SECRET_KEY,
    object = paste(lic$customer, lic$tier, lic$expiry, lic$issued %||% lic$expiry, sep = "|"),
    algo = "sha256"
  )
  if (lic$sig != expected) {
    result$status <- "invalid"
    result$message <- "License signature invalid."
    return(result)
  }

  result$customer <- lic$customer
  result$tier <- lic$tier
  result$expiry <- as.Date(lic$expiry)
  days_left <- as.numeric(result$expiry - Sys.Date())
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
    result$message <- "License expired. Contact mabek@madlangaresearch.co.za to renew."
  }

  # Online phone-home check (fire-and-forget, doesn't block on network failure)
  if (nzchar(VALIDATION_URL)) {
    tryCatch({
      resp <- GET(VALIDATION_URL, query = list(
        key = lic$sig,
        customer = URLencode(lic$customer)
      ), timeout(3))
      if (resp$status_code == 403) {
        result$status <- "expired"
        result$message <- "License revoked. Please contact support."
      }
    }, error = function(e) {})
  }

  result
}
