# inquiry.R — Settings for the inquiry this deployment shows.
#
# The pipeline writes app/inquiry.json from inquiries/<id>/inquiry.json
# (python pipeline/build_db.py --step config). Anything missing falls back
# to the neutral defaults below, so the app still starts without it.

DEFAULT_DISCLAIMER <- paste(
  "Automated analysis of public testimony.",
  "Being named or mentioned is not a finding of wrongdoing, and allegations",
  "made by witnesses are untested until the inquiry reports.",
  "Check every claim against the cited transcript before you publish it."
)

INQUIRY_DEFAULTS <- list(
  id = "inquiry",
  short_name = "Inquiry",
  name = "",
  branding = list(product_name = "Commission Research", vendor = ""),
  contact = list(name = "", email = ""),
  focus_person = list(match = "", legend = ""),
  disclaimer = DEFAULT_DISCLAIMER
)

merge_settings <- function(defaults, overrides) {
  for (k in names(overrides)) {
    v <- overrides[[k]]
    if (is.null(v)) next
    # The publishing disclaimer can be reworded per inquiry but never blanked.
    if (identical(k, "disclaimer") && !nzchar(paste(v, collapse = ""))) next
    defaults[[k]] <- if (is.list(defaults[[k]]) && is.list(v)) merge_settings(defaults[[k]], v) else v
  }
  defaults
}

load_inquiry_settings <- function(path = Sys.getenv("INQUIRY_APP_CONFIG",
                                                    unset = file.path(getwd(), "inquiry.json"))) {
  if (!nzchar(path) || !file.exists(path)) return(INQUIRY_DEFAULTS)
  cfg <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) {
      warning("Ignoring unreadable inquiry settings at ", path, ": ", conditionMessage(e))
      list()
    })
  merge_settings(INQUIRY_DEFAULTS, cfg)
}

INQUIRY <- load_inquiry_settings()

# TRUE for labels that name the inquiry's focus witness (centre of the network).
is_focus_label <- function(label, match = INQUIRY$focus_person$match) {
  if (is.null(match) || !nzchar(match)) return(rep(FALSE, length(label)))
  grepl(tolower(match), tolower(as.character(label)), fixed = TRUE)
}

# "Contact Mabek at x@y" when a contact is configured, else NULL.
contact_line <- function(contact = INQUIRY$contact) {
  email <- contact$email %||% ""
  if (!nzchar(email)) return(NULL)
  who <- contact$name %||% ""
  tagList("Contact ", if (nzchar(who)) tagList(tags$b(who), " at "),
          tags$a(href = paste0("mailto:", email), email))
}
