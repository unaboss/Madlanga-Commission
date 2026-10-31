# auth.R — Customer logins for the dashboard.
#
# Each deployment keeps its own accounts in a SQLite file (MADLANGA_USERS_DB,
# default app/data/users.db). Passwords are stored as sodium (scrypt) hashes.
# A successful login sets a random session token in a cookie; only a hash of
# the token is stored, and the dashboard UI and server are only built for a
# request that carries a live token.
#
# Roles:  admin   — everything, plus the Users tab
#         analyst — read everything, save notes and flags
#         viewer  — read only
#
# Logins are on unless MADLANGA_AUTH=off or MADLANGA_DEV_MODE=true.
# Create the first admin with:  Rscript tools/manage_users.R add <name> --role admin

AUTH_DB_PATH <- Sys.getenv("MADLANGA_USERS_DB",
  unset = file.path(getwd(), "data", "users.db"))
AUTH_COOKIE <- "cr_session"
AUTH_ROLES <- c("admin", "analyst", "viewer")
SESSION_HOURS <- 12
MAX_FAILED_LOGINS <- 5
LOCKOUT_MINUTES <- 15
MIN_PASSWORD_CHARS <- 10

auth_enabled <- function(setting = Sys.getenv("MADLANGA_AUTH", unset = "on"),
                         dev_mode = DEV_MODE) {
  !dev_mode && !(tolower(setting) %in% c("off", "false", "0", "no"))
}

now_utc <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")

# ── Storage ──────────────────────────────────────────────────────
auth_db <- function(path = AUTH_DB_PATH) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- dbConnect(SQLite(), path)
  dbExecute(con, "PRAGMA busy_timeout = 5000")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS users (
      username TEXT PRIMARY KEY COLLATE NOCASE,
      display_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('admin', 'analyst', 'viewer')),
      disabled INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      last_login TEXT)")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      username TEXT NOT NULL COLLATE NOCASE,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL)")
  dbExecute(con, "CREATE TABLE IF NOT EXISTS auth_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at TEXT NOT NULL,
      username TEXT COLLATE NOCASE,
      event TEXT NOT NULL,
      detail TEXT)")
  con
}

log_auth_event <- function(con, username, event, detail = "") {
  dbExecute(con, "INSERT INTO auth_events (at, username, event, detail) VALUES (?, ?, ?, ?)",
            params = list(now_utc(), username %||% "", event, detail %||% ""))
}

hash_token <- function(token) digest::digest(token, algo = "sha256", serialize = FALSE)

check_password_policy <- function(password) {
  if (nchar(password %||% "") < MIN_PASSWORD_CHARS)
    stop("Passwords need at least ", MIN_PASSWORD_CHARS, " characters.")
  invisible(TRUE)
}

clean_username <- function(username) {
  u <- trimws(username %||% "")
  if (!grepl("^[A-Za-z0-9._@-]{2,64}$", u))
    stop("Usernames are 2 to 64 letters, digits, dots, dashes, underscores or @.")
  u
}

# ── Accounts ─────────────────────────────────────────────────────
create_user <- function(con, username, password, role = "analyst", display_name = NULL) {
  username <- clean_username(username)
  if (!role %in% AUTH_ROLES) stop("Role must be one of: ", paste(AUTH_ROLES, collapse = ", "))
  check_password_policy(password)
  if (nrow(get_user(con, username)) > 0) stop("A user called '", username, "' already exists.")
  dbExecute(con, "INSERT INTO users (username, display_name, password_hash, role, created_at)
                  VALUES (?, ?, ?, ?, ?)",
    params = list(username, trimws(display_name %||% username), sodium::password_store(password),
                  role, now_utc()))
  log_auth_event(con, username, "user_created", role)
  invisible(username)
}

get_user <- function(con, username) {
  dbGetQuery(con, "SELECT username, display_name, role, disabled, created_at, last_login
                   FROM users WHERE username = ?", params = list(trimws(username %||% "")))
}

list_users <- function(con) {
  dbGetQuery(con, "SELECT username, display_name, role, disabled, created_at, last_login
                   FROM users ORDER BY username COLLATE NOCASE")
}

set_password <- function(con, username, password) {
  check_password_policy(password)
  n <- dbExecute(con, "UPDATE users SET password_hash = ? WHERE username = ?",
                 params = list(sodium::password_store(password), username))
  if (n == 0) stop("No user called '", username, "'.")
  # A new password signs the user out everywhere.
  dbExecute(con, "DELETE FROM sessions WHERE username = ?", params = list(username))
  log_auth_event(con, username, "password_set")
  invisible(TRUE)
}

set_role <- function(con, username, role) {
  if (!role %in% AUTH_ROLES) stop("Role must be one of: ", paste(AUTH_ROLES, collapse = ", "))
  n <- dbExecute(con, "UPDATE users SET role = ? WHERE username = ?", params = list(role, username))
  if (n == 0) stop("No user called '", username, "'.")
  log_auth_event(con, username, "role_set", role)
  invisible(TRUE)
}

set_disabled <- function(con, username, disabled = TRUE) {
  n <- dbExecute(con, "UPDATE users SET disabled = ? WHERE username = ?",
                 params = list(as.integer(disabled), username))
  if (n == 0) stop("No user called '", username, "'.")
  if (disabled) dbExecute(con, "DELETE FROM sessions WHERE username = ?", params = list(username))
  log_auth_event(con, username, if (disabled) "user_disabled" else "user_enabled")
  invisible(TRUE)
}

# ── Logging in ───────────────────────────────────────────────────
recent_failures <- function(con, username, minutes = LOCKOUT_MINUTES) {
  since <- format(Sys.time() - minutes * 60, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  dbGetQuery(con, "SELECT COUNT(*) AS n FROM auth_events
                   WHERE username = ? AND event = 'login_failed' AND at >= ?
                     AND at > COALESCE((SELECT MAX(at) FROM auth_events
                                        WHERE username = ? AND event = 'login_ok'), '')",
             params = list(username, since, username))$n
}

# Returns list(ok, user, message). The message never says whether the
# username exists.
attempt_login <- function(con, username, password, ip = "") {
  username <- trimws(username %||% "")
  fail <- list(ok = FALSE, user = NULL, message = "Wrong username or password.")
  if (!nzchar(username) || !nzchar(password %||% "")) return(fail)

  if (recent_failures(con, username) >= MAX_FAILED_LOGINS) {
    log_auth_event(con, username, "login_locked", ip)
    return(list(ok = FALSE, user = NULL, message = paste0(
      "Too many failed attempts. Try again in ", LOCKOUT_MINUTES, " minutes.")))
  }
  row <- dbGetQuery(con, "SELECT username, password_hash, disabled FROM users WHERE username = ?",
                    params = list(username))
  ok <- nrow(row) == 1 && sodium::password_verify(row$password_hash, password)
  if (!ok || isTRUE(row$disabled == 1)) {
    log_auth_event(con, username, "login_failed", ip)
    return(fail)
  }
  dbExecute(con, "UPDATE users SET last_login = ? WHERE username = ?",
            params = list(now_utc(), row$username))
  log_auth_event(con, row$username, "login_ok", ip)
  list(ok = TRUE, user = as.list(get_user(con, row$username)), message = "")
}

# Starts a session and returns the raw token for the cookie.
issue_session <- function(con, username, hours = SESSION_HOURS) {
  token <- sodium::bin2hex(sodium::random(32))
  expires <- format(Sys.time() + hours * 3600, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  dbExecute(con, "DELETE FROM sessions WHERE expires_at < ?", params = list(now_utc()))
  dbExecute(con, "INSERT INTO sessions (token_hash, username, created_at, expires_at)
                  VALUES (?, ?, ?, ?)",
            params = list(hash_token(token), username, now_utc(), expires))
  token
}

# The signed-in user for a token, or NULL when it is missing, expired or
# belongs to a disabled account.
session_user <- function(con, token) {
  if (is.null(token) || !nzchar(token)) return(NULL)
  row <- dbGetQuery(con, "SELECT u.username, u.display_name, u.role
                          FROM sessions s JOIN users u ON u.username = s.username
                          WHERE s.token_hash = ? AND s.expires_at > ? AND u.disabled = 0",
                    params = list(hash_token(token), now_utc()))
  if (nrow(row) == 0) NULL else as.list(row[1, ])
}

end_session <- function(con, token) {
  if (is.null(token) || !nzchar(token)) return(invisible(FALSE))
  user <- session_user(con, token)
  dbExecute(con, "DELETE FROM sessions WHERE token_hash = ?", params = list(hash_token(token)))
  if (!is.null(user)) log_auth_event(con, user$username, "logout")
  invisible(TRUE)
}

read_cookie <- function(header, name = AUTH_COOKIE) {
  if (is.null(header) || !nzchar(header)) return(NULL)
  parts <- trimws(strsplit(header, ";", fixed = TRUE)[[1]])
  hit <- parts[startsWith(parts, paste0(name, "="))]
  if (length(hit) == 0) NULL else utils::URLdecode(sub(paste0("^", name, "="), "", hit[1]))
}

request_user <- function(req, path = AUTH_DB_PATH) {
  token <- read_cookie(req$HTTP_COOKIE)
  if (is.null(token)) return(NULL)
  con <- auth_db(path)
  on.exit(dbDisconnect(con))
  session_user(con, token)
}

# Who is using this Shiny session: the logged-in account, else a name
# provided by the host (Posit Connect), else NULL.
current_user <- function(session) {
  session$userData$auth_user %||% (if (!is.null(session$user)) list(
    username = session$user, display_name = session$user, role = "analyst"))
}

current_username <- function(session) current_user(session)$username

can_write_notes <- function(session) {
  u <- current_user(session)
  is.null(u) || u$role %in% c("admin", "analyst")
}

# ── Shiny: login page and wrappers ───────────────────────────────
AUTH_JS <- "
Shiny.addCustomMessageHandler('cr-auth', function(m) {
  var path = window.location.pathname.replace(/[^/]*$/, '');
  var secure = window.location.protocol === 'https:' ? '; Secure' : '';
  if (m.token) {
    document.cookie = m.cookie + '=' + encodeURIComponent(m.token) + '; Max-Age=' + m.maxAge +
      '; Path=' + path + '; SameSite=Strict' + secure;
  } else {
    document.cookie = m.cookie + '=; Max-Age=0; Path=' + path + '; SameSite=Strict' + secure;
  }
  window.location.reload();
});
"

login_page <- function(theme = NULL) {
  page_fillable(
    theme = theme,
    title = paste(INQUIRY$branding$product_name, "— Sign in"),
    tags$head(tags$script(HTML(AUTH_JS))),
    div(style = "max-width:380px; margin:12vh auto 0; width:100%;",
      card(
        card_header(
          div(tags$b(INQUIRY$branding$product_name),
              tags$div(class = "text-muted", style = "font-size:0.85rem;", INQUIRY$short_name))),
        card_body(
          textInput("auth_username", "Username", width = "100%"),
          passwordInput("auth_password", "Password", width = "100%"),
          tags$script(HTML(
            "$(document).on('keyup', '#auth_password', function(e) {
               if (e.key === 'Enter') $('#auth_login').click(); });")),
          actionButton("auth_login", "Sign in", class = "btn-primary", width = "100%"),
          uiOutput("auth_message"),
          if (!is.null(contact_line()))
            p(class = "text-muted", style = "font-size:0.8rem; margin-top:12px;",
              "No account? ", contact_line(), ".")
        )
      )
    )
  )
}

login_server <- function(input, output, session, path = AUTH_DB_PATH) {
  message <- reactiveVal("")
  output$auth_message <- renderUI({
    if (nzchar(message()))
      div(class = "text-danger", style = "margin-top:10px; font-size:0.85rem;", message())
  })
  observeEvent(input$auth_login, {
    con <- auth_db(path)
    on.exit(dbDisconnect(con))
    ip <- session$request$HTTP_X_FORWARDED_FOR %||% session$request$REMOTE_ADDR %||% ""
    res <- attempt_login(con, input$auth_username, input$auth_password, ip)
    if (!res$ok) {
      message(res$message)
      return()
    }
    session$sendCustomMessage("cr-auth", list(
      cookie = AUTH_COOKIE, token = issue_session(con, res$user$username),
      maxAge = SESSION_HOURS * 3600))
  })
}

# Serve the dashboard only to signed-in requests; everyone else gets the
# login page. `app_ui` is a function(user) so admin-only tabs can be added.
secure_ui <- function(app_ui, theme = NULL) {
  function(req) {
    if (!auth_enabled()) return(app_ui(NULL))
    user <- request_user(req)
    if (is.null(user)) login_page(theme) else app_ui(user)
  }
}

secure_server <- function(app_server) {
  function(input, output, session) {
    if (!auth_enabled()) return(app_server(input, output, session))
    token <- read_cookie(session$request$HTTP_COOKIE)
    user <- if (is.null(token)) NULL else local({
      con <- auth_db()
      on.exit(dbDisconnect(con))
      session_user(con, token)
    })
    if (is.null(user)) return(login_server(input, output, session))

    session$userData$auth_user <- user
    session$userData$auth_token <- token
    observeEvent(input$auth_logout, {
      con <- auth_db()
      on.exit(dbDisconnect(con))
      end_session(con, token)
      session$sendCustomMessage("cr-auth", list(cookie = AUTH_COOKIE, token = NULL))
    })
    app_server(input, output, session)
  }
}

# Navbar items: who is signed in and a sign-out link.
auth_nav_items <- function(user) {
  if (is.null(user)) return(NULL)
  nav_menu(
    title = tagList(icon("user"), " ", user$display_name),
    align = "right",
    nav_item(div(style = "padding:6px 15px; font-size:0.8rem; color:#aaa;",
                 user$username, " · ", user$role)),
    nav_item(actionLink("auth_logout", tagList(icon("right-from-bracket"), " Sign out"),
                        style = "padding:6px 15px; display:block;"))
  )
}

# ── Users tab (admins only) ──────────────────────────────────────
users_admin_ui <- function() {
  layout_columns(
    col_widths = c(4, 8),
    card(
      card_header("Add a user"),
      card_body(
        textInput("ua_username", "Username"),
        textInput("ua_display", "Full name"),
        selectInput("ua_role", "Role", choices = c(
          "Analyst (read, notes)" = "analyst", "Viewer (read only)" = "viewer",
          "Admin (manages users)" = "admin")),
        passwordInput("ua_password", paste0("Password (", MIN_PASSWORD_CHARS, "+ characters)")),
        actionButton("ua_add", "Add user", class = "btn-primary", icon = icon("user-plus"))
      )
    ),
    card(
      card_header("Users"),
      card_body(
        reactableOutput("ua_table"),
        div(style = "display:flex; gap:8px; flex-wrap:wrap; margin-top:10px;",
          passwordInput("ua_new_password", NULL, placeholder = "New password for selected user"),
          actionButton("ua_reset", "Set password", class = "btn-sm btn-outline-primary"),
          actionButton("ua_toggle", "Disable / enable", class = "btn-sm btn-outline-danger"))
      )
    )
  )
}

users_admin_server <- function(input, output, session) {
  me <- current_user(session)
  if (is.null(me) || me$role != "admin") return(invisible())
  bump <- reactiveVal(0)
  users <- reactive({
    bump()
    con <- auth_db(); on.exit(dbDisconnect(con))
    list_users(con)
  })
  with_db <- function(expr_fn, done) {
    con <- auth_db(); on.exit(dbDisconnect(con))
    ok <- tryCatch({ expr_fn(con); TRUE },
                   error = function(e) { showNotification(conditionMessage(e), type = "error"); FALSE })
    if (ok) { bump(bump() + 1); showNotification(done, type = "message") }
    ok
  }
  selected <- function() {
    sel <- getReactableState("ua_table", "selected")
    df <- users()
    if (is.null(sel) || sel > nrow(df)) { showNotification("Select a user first.", type = "warning"); return(NULL) }
    df$username[sel]
  }

  output$ua_table <- renderReactable({
    df <- users()
    df$status <- ifelse(df$disabled == 1, "Disabled", "Active")
    reactable(df[, c("username", "display_name", "role", "status", "last_login")],
      columns = list(username = colDef(name = "Username"), display_name = colDef(name = "Name"),
                     role = colDef(name = "Role", width = 90), status = colDef(name = "Status", width = 90),
                     last_login = colDef(name = "Last sign-in (UTC)")),
      selection = "single", onClick = "select", compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"),
        rowSelectedStyle = list(backgroundColor = "#1a3a5c")))
  })

  observeEvent(input$ua_add, {
    if (with_db(function(con) create_user(con, input$ua_username, input$ua_password,
                                          input$ua_role, input$ua_display),
                paste0("Added ", input$ua_username, "."))) {
      updateTextInput(session, "ua_username", value = "")
      updateTextInput(session, "ua_display", value = "")
      updateTextInput(session, "ua_password", value = "")
    }
  })
  observeEvent(input$ua_reset, {
    u <- selected(); req(u)
    if (with_db(function(con) set_password(con, u, input$ua_new_password),
                paste0("Password changed for ", u, ". They have been signed out.")))
      updateTextInput(session, "ua_new_password", value = "")
  })
  observeEvent(input$ua_toggle, {
    u <- selected(); req(u)
    if (tolower(u) == tolower(me$username)) {
      showNotification("You can't disable your own account.", type = "warning")
      return()
    }
    now_disabled <- users()$disabled[tolower(users()$username) == tolower(u)] == 1
    with_db(function(con) set_disabled(con, u, !now_disabled),
            paste0(u, if (now_disabled) " can sign in again." else " is disabled and signed out."))
  })
}
