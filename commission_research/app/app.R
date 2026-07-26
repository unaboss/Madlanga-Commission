# app.R — Commission Research Tool
# Professional intelligence dashboard for the Madlanga Commission of Inquiry
source("global.R")

library(shiny)
library(bslib)
library(visNetwork)
library(plotly)
library(reactable)
library(DT)

# ── Theme ───────────────────────────────────────────────────────
DARK_THEME <- bs_theme(
  version = 5,
  bootswatch = "darkly",
  primary = "#3498db",
  secondary = "#6c757d",
  success = "#27ae60",
  info = "#2980b9",
  warning = "#f39c12",
  danger = "#e74c3c",
  base_font = font_google("Inter"),
  heading_font = font_google("Inter"),
  "navbar-bg" = "#1a1a1a",
  "body-bg" = "#121212",
  "card-bg" = "#1e1e1e",
  "card-cap-bg" = "#2a2a2a"
)

# ── Role colors ─────────────────────────────────────────────────
ROLE_COLORS <- c(
  witness           = "#2ecc71",
  witness_protected = "#e74c3c"
)

ROLE_ICONS <- c(
  witness           = "user",
  witness_protected = "user-secret"
)

# ── Concentric Bipartite Layout ────────────────────────────────
layout_concentric <- function(nodes_df, edges_df,
                               inner_radius = 130,
                               outer_radius = 350) {
  is_person <- nodes_df$group %in% c("witness", "witness_protected")
  person_ids <- nodes_df$id[is_person]
  entity_ids <- nodes_df$id[!is_person]
  n_persons <- sum(is_person)
  if (n_persons == 0 || length(entity_ids) == 0) return(nodes_df)

  conn_count <- sapply(person_ids, function(pid)
    sum(edges_df$from == pid | edges_df$to == pid, na.rm = TRUE))
  order_by_conn <- order(conn_count, decreasing = TRUE)
  angles <- 2 * pi * (seq_len(n_persons) - 1) / n_persons
  angles <- angles[order_by_conn]
  nodes_df$x[is_person] <- inner_radius * cos(angles)
  nodes_df$y[is_person] <- inner_radius * sin(angles)

  p_angle_map <- setNames(angles, person_ids)
  ent_angles <- sapply(entity_ids, function(eid) {
    conn <- edges_df$from[edges_df$to == eid]
    conn <- c(conn, edges_df$to[edges_df$from == eid])
    conn <- conn[conn %in% person_ids]
    a <- p_angle_map[as.character(conn)]
    a <- a[!is.na(a)]
    if (length(a) < 2) return(if (length(a) == 1) a else NA)
    atan2(mean(sin(a)), mean(cos(a)))
  })
  na_idx <- is.na(ent_angles)
  if (any(na_idx))
    ent_angles[na_idx] <- seq(-pi, pi, length.out = sum(na_idx) + 2)[-c(1, sum(na_idx) + 2)]
  if (length(ent_angles) > 1) {
    o <- order(ent_angles)
    min_gap <- 2 * pi / length(ent_angles) * 0.7
    for (i in seq_along(ent_angles)[-1]) {
      gap <- ent_angles[o[i]] - ent_angles[o[i - 1]]
      if (gap < min_gap) ent_angles[o[i]] <- ent_angles[o[i - 1]] + min_gap
    }
  }
  nodes_df$x[!is_person] <- outer_radius * cos(ent_angles)
  nodes_df$y[!is_person] <- outer_radius * sin(ent_angles)

  ci <- grep("Mkhwanazi", nodes_df$label, ignore.case = TRUE)
  if (length(ci)) { nodes_df$x[ci] <- 0; nodes_df$y[ci] <- 0 }
  nodes_df
}

# ── UI ──────────────────────────────────────────────────────────
ui <- page_navbar(
  title = tags$span(
    tags$img(src = "", style = "display:none"),
    "Commission Research"
  ),
  theme = DARK_THEME,
  id = "nav",
  footer = div(
    style = "text-align:center; padding:15px; font-size:0.75rem; color:#666; border-top:1px solid #2a2a2a; margin-top:20px;",
    "\u00a9 2026 Open Eye Data Analyst. All rights reserved."
  ),
  header = tagList(
    tags$head(
      tags$style(HTML("
      .stat-card { text-align: center; padding: 20px 10px; border-radius: 8px; }
      .stat-card h2 { font-size: 2rem; margin: 5px 0; font-weight: 700; }
      .stat-card p { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 1px; opacity: 0.7; margin: 0; }
      .role-card { border-left: 4px solid; padding: 12px; margin-bottom: 8px; border-radius: 4px; font-size: 0.85rem; color: #ecf0f1; }
      .role-card strong { font-size: 1rem; color: #ecf0f1; }
      .role-card small { color: #bdc3c7; }
      .entity-tag { display: inline-block; padding: 2px 10px; margin: 3px; border-radius: 12px;
                    font-size: 0.75rem; background: #1a3a5c; color: #3498db; cursor: pointer; }
      .entity-tag:hover { background: #3498db; color: white; }
      .nav-link { font-size: 0.9rem; }
      .navbar { border-bottom: 1px solid #333 !important; }
      .navbar .nav-link { color: #ccc !important; }
      .navbar .nav-link:hover, .navbar .nav-link:focus { color: #fff !important; }
      .navbar .nav-link.active { color: #fff !important; border-bottom: 2px solid #888; }
      .navbar .navbar-brand, .navbar .navbar-brand * { color: #fff !important; }
      .navbar .dropdown-menu { background: #222 !important; border: 1px solid #444 !important; }
      .navbar .dropdown-item { color: #ccc !important; }
      .navbar .dropdown-item:hover { background: #333 !important; color: #fff !important; }
      .navbar .dropdown-divider { border-color: #444 !important; }
    "))
  )),

  # ── Overview ─────────────────────────────────────────────────
  nav_panel(
    title = "Overview",
    layout_columns(
      col_widths = c(8, 4),
      card(
        full_screen = TRUE, style = "min-height: 450px;",
        card_header("Case Network"),
        card_body(visNetworkOutput("overview_network", height = "390px")),
        card_footer(
          div(style = "display:flex; justify-content:space-between; align-items:center;",
            actionButton("legend_btn", "Show Legend",
              class = "btn-sm btn-outline-secondary"),
            tags$small(class = "text-muted", "Click a node or edge for details")
          )
        )
      ),
      card(
        full_screen = TRUE, style = "min-height: 450px;",
        card_header(
          div(style = "display:flex; align-items:center; gap:8px;",
            "Top Entities",
            actionButton("ent_toggle", "Show All \u25BC",
              class = "btn-sm btn-outline-secondary")
          )
        ),
        card_body(uiOutput("overview_entities"))
      )
    ),
    card(
      style = "min-height: 120px;",
      card_header(textOutput("overview_detail_header")),
      card_body(uiOutput("overview_detail_panel"))
    )
  ),

  # ── Connections Graph ─────────────────────────────────────────
  nav_panel(
    title = "Connections",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        h6("Connection Type"),
        radioButtons("conn_edge_type", NULL,
          choices = c("All connections" = "all",
                      "Questioning" = "questioning",
                      "Co-testified" = "co_testified",
                      "Mentions" = "mentions"),
          selected = "all"
        ),
        hr(),
        h6("Filter Nodes"),
        checkboxGroupInput("net_roles", "Show roles:",
          choices = names(ROLE_COLORS),
          selected = names(ROLE_COLORS)
        ),
        sliderInput("net_min_edges", "Min connections:", 0, 100, 0, step = 5),
        hr(),
        h6("Selected Node"),
        textOutput("net_debug"),
        uiOutput("net_node_info"),
        hr(),
        actionButton("net_reset", "Reset View", class = "btn-sm btn-outline-secondary",
                     width = "100%")
      ),
      card(
        full_screen = TRUE, style = "min-height: 650px;",
        card_header(textOutput("net_header")),
        card_body(visNetworkOutput("network_graph", height = "620px"))
      )
    )
  ),

  # ── Witnesses and Entities ────────────────────────────────────
  nav_panel(
    title = "Witnesses and Entities",
    layout_sidebar(
      sidebar = sidebar(
        width = 350,
        h6("Role Categories"),
        selectInput("roles_filter", NULL,
          choices = c("All", names(ROLE_COLORS)),
          selected = "All"
        ),
        hr(),
        uiOutput("witness_entity_detail")
      ),
      uiOutput("role_cards")
    )
  ),

  # ── Attention Map ────────────────────────────────────────────
  nav_panel(
    title = "Attention Map",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        h6("Heatmap: Who Questioned Whom"),
        p("Row = evidence leader / commissioner, Column = witness.",
          style = "font-size:0.85rem;", class = "text-muted"),
        sliderInput("att_top_n", "Show top N:",
          min = 5, max = 15, value = 10, step = 1),
        hr(),
        h6("Selected Interaction"),
        uiOutput("att_detail")
      ),
      card(
        full_screen = TRUE, style = "min-height: 650px;",
        card_header("Questioning Attention Matrix"),
        card_body(
          plotlyOutput("attention_heatmap", height = "620px")
        )
      )
    )
  ),

  # ── Timeline ─────────────────────────────────────────────────
  nav_panel(
    title = "Timeline",
    card(
      full_screen = TRUE, style = "min-height: 600px;",
      card_header("Hearing Timeline"),
      card_body(
        plotlyOutput("timeline_plot", height = "350px"),
        hr(),
        reactableOutput("timeline_table")
      )
    )
  ),

  # ── Search ───────────────────────────────────────────────────
  nav_panel(
    title = "Search",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        textInput("search_q", NULL, placeholder = "Type search query..."),
        dateInput("search_from", "From", value = NULL),
        dateInput("search_to", "To", value = NULL),
        selectizeInput("search_spk", "Speaker", choices = NULL, multiple = TRUE,
                       options = list(placeholder = "Filter by speaker")),
        hr(),
        h6("Syntax"),
        tags$small(
          tags$code("word"), " — keyword",
          tags$br(), tags$code('"exact phrase"'), " — phrase",
          tags$br(), tags$code("CARRI*"), " — wildcard",
          tags$br(), tags$code("A AND B"), " — boolean"
        )
      ),
      card(
        full_screen = TRUE,
        card_header(textOutput("search_header")),
        card_body(reactableOutput("search_results"))
      )
    )
  ),

  # ── Entities ─────────────────────────────────────────────────
  nav_panel(
    title = "Entities",
    layout_sidebar(
      sidebar = sidebar(
        width = 280,
        h6("Organizations"),
        reactableOutput("ent_list")
      ),
      card(
        full_screen = TRUE,
        card_header(textOutput("ent_header")),
        card_body(uiOutput("ent_detail"))
      )
    )
  ),

  # ── Story Map ────────────────────────────────────────────────
  nav_panel(
    title = "Story Map",
    layout_sidebar(
      sidebar = sidebar(
        width = 280,
        h6("Filters"),
        dateRangeInput("story_dates", "Date range",
          start = "2025-08-15", end = "2026-07-31"),
        selectizeInput("story_entity", "Topic / Entity",
          choices = NULL, multiple = TRUE,
          options = list(placeholder = "Filter by topic...")),
        selectizeInput("story_witness", "Witness",
          choices = NULL, multiple = TRUE,
          options = list(placeholder = "Filter by witness...")),
        hr(),
        checkboxInput("story_show_links", "Highlight cross-references", value = FALSE),
        hr(),
        h6("Key Topics"),
        uiOutput("story_quick_entities")
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(
          style = "min-height: 480px;",
          card_header(
            tags$span(class = "text-warning", " Commission Evidence")
          ),
          card_body(
            plotlyOutput("story_comm_plot", height = "220px"),
            hr(),
            reactableOutput("story_comm_table")
          )
        ),
        card(
          style = "min-height: 480px;",
          card_header(
            tags$span(class = "text-success", " Witness Testimony")
          ),
          card_body(
            plotlyOutput("story_wit_plot", height = "220px"),
            hr(),
            reactableOutput("story_wit_table")
          )
        )
      ),
      card(
        card_header(textOutput("story_detail_header")),
        card_body(uiOutput("story_detail_panel"))
      )
    )
  ),

  # ── Evidence Compare ─────────────────────────────────────────
  nav_panel(
    title = "Evidence Compare",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        h6("Select Topic"),
        selectizeInput("ec_entity", "Entity / Topic",
          choices = NULL, multiple = FALSE,
          options = list(placeholder = "Type to search for an entity...")),
        selectInput("ec_type", "Entity Type",
          choices = c("Any", "organization", "case_reference", "exhibit",
                      "location", "money", "date", "vehicle"),
          selected = "Any"),
        hr(),
        h6("Results"),
        uiOutput("ec_summary"),
        hr(),
        uiOutput("ec_bundle_button"),
        hr(),
        tags$small(class = "text-muted",
          "Select an entity above to compare what the commission's documents and witnesses say about it.")
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(
          style = "min-height: 380px;",
          card_header(tags$span(class = "text-warning", "Commission Documents")),
          card_body(reactableOutput("ec_docs_table"))
        ),
        card(
          style = "min-height: 380px;",
          card_header(tags$span(class = "text-success", "Witness Testimony")),
          card_body(reactableOutput("ec_wit_table"))
        )
      ),
      card(
        card_header(textOutput("ec_detail_header")),
        card_body(uiOutput("ec_detail_panel"))
      )
    )
  ),

  # ── Contradictions ────────────────────────────────────────────
  nav_panel(
    title = "Contradictions",
    layout_sidebar(
      sidebar = sidebar(
        width = 300,
        h6("Contradiction Detection"),
        p("Entities mentioned by multiple witnesses. Review statements side by side to find contradictions.",
          class = "text-muted", style = "font-size:0.85rem;"),
        hr(),
        h6("Filter"),
        selectInput("contradiction_type", "Entity Type",
          choices = c("All", "organization", "person", "location", "case_reference", "exhibit", "money", "date", "vehicle"),
          selected = "All"),
        sliderInput("contradiction_min_wit", "Min witnesses", 2, 20, 2, step = 1),
        hr(),
        h6("Selected Entity"),
        uiOutput("contradiction_summary")
      ),
      layout_columns(
        col_widths = c(5, 7),
        card(
          full_screen = TRUE,
          card_header(textOutput("contradiction_list_header")),
          card_body(reactableOutput("contradiction_list"))
        ),
        card(
          full_screen = TRUE,
          card_header(textOutput("contradiction_detail_header")),
          card_body(uiOutput("contradiction_detail"))
        )
      )
    )
  ),

  # ── Dashboard ─────────────────────────────────────────────────
  nav_panel(
    title = "Dashboard",
    card(
    full_screen = TRUE, style = "margin-top:10px;",
    card_header(
      div(style = "display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px;",
        span("All Accusations"),
        selectInput("acc_filter", NULL, width = 280,
          choices = c("All Accusations" = "all",
            "Critical (murder, kill, death, threat, violence)" = "critical",
            "High (bribe, fraud, theft, embezzle, kickback)" = "high",
            "Medium (leak, cover up, obstruction, conspiracy)" = "medium",
            "Uncategorized (none of the above)" = "uncategorized"))
      )
    ),
    card_body(reactableOutput("dash_accusations_table"))
  ),
  layout_columns(
    col_widths = c(6, 6),
    card(
      full_screen = TRUE,
      card_header("Top 10 Most Mentioned Witnesses"),
      card_body(reactableOutput("dash_mentioned_table"))
    ),
    card(
      full_screen = TRUE,
      card_header("Witness Reliability"),
      card_body(reactableOutput("dash_reliability_table"))
    )
  ),
  card(
    full_screen = TRUE,
    card_header("Evidence Corroboration"),
      card_body(
        layout_columns(
          col_widths = c(4, 8),
          card(
            card_body(
              h3(textOutput("dash_validity_pct", inline = TRUE)),
              p("of accused entities have documentary corroboration"),
              p(textOutput("dash_validity_detail"), class = "text-muted", style = "font-size:0.85rem;")
            )
          ),
          card(
            card_body(reactableOutput("dash_validity_table"))
          )
        )
      )
    )
  ),
  nav_spacer(),
  nav_item(uiOutput("license_status")),
  nav_menu("Stats",
    nav_item(div(style = "padding:8px 15px; white-space:nowrap;",
      span(style = "font-weight:700;font-size:1.2rem;color:#3498db;", textOutput("stat_hearings", inline = TRUE)),
      span(style = "font-size:0.75rem;text-transform:uppercase;opacity:0.7;color:#ecf0f1;margin-left:5px;", "Hearings")
    )),
    nav_item(div(style = "padding:8px 15px; white-space:nowrap;",
      span(style = "font-weight:700;font-size:1.2rem;color:#27ae60;", textOutput("stat_speakers", inline = TRUE)),
      span(style = "font-size:0.75rem;text-transform:uppercase;opacity:0.7;color:#ecf0f1;margin-left:5px;", "Witnesses")
    )),
    nav_item(div(style = "padding:8px 15px; white-space:nowrap;",
      span(style = "font-weight:700;font-size:1.2rem;color:#f39c12;", textOutput("stat_segments", inline = TRUE)),
      span(style = "font-size:0.75rem;text-transform:uppercase;opacity:0.7;color:#ecf0f1;margin-left:5px;", "Segments")
    )),
    nav_item(div(style = "padding:8px 15px; white-space:nowrap;",
      span(style = "font-weight:700;font-size:1.2rem;color:#8e44ad;", textOutput("stat_entities", inline = TRUE)),
      span(style = "font-size:0.75rem;text-transform:uppercase;opacity:0.7;color:#ecf0f1;margin-left:5px;", "Entities")
    )),
    nav_item(div(style = "padding:6px 15px; border-bottom:1px solid #444;")),
    nav_item(div(style = "padding:6px 15px;",
      tags$b(style = "font-size:0.75rem; text-transform:uppercase; opacity:0.7;", "Top Mentioned"),
      uiOutput("stat_top_mentioned")
    ))
  )
)

# ── Server ──────────────────────────────────────────────────────
server <- function(input, output, session) {

  conn <- get_db()
  onStop(function() { dbDisconnect(conn) })

  net <- load_network()
  att <- load_attention()

  # ── License status ────────────────────────────────────────────
  output$license_status <- renderUI({
    if (LICENSE$status == "valid") {
      div(style = "padding:4px 12px; font-size:0.75rem; white-space:nowrap; color:#27ae60;",
        icon("check-circle"), " Licensed — ", LICENSE$expiry)
    } else if (LICENSE$status == "grace_period") {
      div(style = "padding:4px 12px; font-size:0.75rem; white-space:nowrap; color:#f39c12;",
        icon("exclamation-triangle"), " License expires in ", LICENSE$grace_left, " days")
    } else {
      div(style = "padding:4px 12px; font-size:0.75rem; white-space:nowrap; color:#e74c3c;",
        icon("lock"), " License expired")
    }
  })

  observe({
    if (LICENSE$status == "expired") {
      showModal(modalDialog(
        title = div(style = "color:#e74c3c;", icon("lock"), " License Expired"),
        h4("Access to the Commission Research Dashboard has been blocked."),
        p("Your license has expired. To continue using the dashboard, please renew your subscription."),
        p(
          "Contact ", tags$b("Mabek"),
          " at ", tags$a(href = "mailto:mabek@madlangaresearch.co.za", "mabek@madlangaresearch.co.za"),
          " to renew."
        ),
        tags$hr(),
        p("After renewing, place the new license.key file in the app directory and click below.",
          class = "text-muted", style = "font-size:0.85rem;"),
        footer = actionButton("renew_check", "Check for Updated License",
          class = "btn-primary", icon = icon("refresh"),
          style = "width:100%;"),
        size = "m", easyClose = FALSE, fade = FALSE
      ))
    }
  })

  observeEvent(input$renew_check, {
    lic <- validate_license()
    if (lic$status != "expired") {
      removeModal()
      session$reload()
    } else {
      showNotification(
        "License still expired. Ensure the new license.key file is in the app directory.",
        type = "error", duration = 8
      )
    }
  })

  # ── Overview Stats ───────────────────────────────────────────
  output$stat_hearings <- renderText({ net$stats$total_hearings })
  output$stat_speakers <- renderText({ net$stats$total_speakers })
  output$stat_segments <- renderText({ format(net$stats$total_segments, big.mark = ",") })
  output$stat_entities <- renderText({ format(net$stats$total_entities, big.mark = ",") })

  output$stat_top_mentioned <- renderUI({
    top <- net$stats$top_mentioned
    if (is.null(top) || length(top) == 0) return(NULL)
    tagList(lapply(seq_len(min(length(top), 5)), function(i) {
      tags$div(style = "font-size:0.78rem; padding:1px 0; color:#ccc;",
        tags$span(style = "color:#888;margin-right:4px;", paste0(i, ".")),
        tags$span(top[[i]]$name),
        tags$span(style = "color:#888;margin-left:6px;font-size:0.7rem;",
                  paste0(top[[i]]$count, "x"))
      )
    }))
  })

  # ── Dashboard ─────────────────────────────────────────────────
  sm <- load_story_map()

  output$dash_hearings <- renderText({ net$stats$total_hearings })
  output$dash_witnesses <- renderText({ net$stats$total_speakers })
  output$dash_segments <- renderText({ format(net$stats$total_segments, big.mark = ",") })
  output$dash_documents <- renderText({ sm$stats$total_commission_events })

  output$dash_accusations <- renderText({
    df <- get_accusation_stats(conn)
    format(sum(df$total_mentions), big.mark = ",")
  })

  output$dash_corroborated <- renderText({ sm$stats$total_shared_entities })

  output$dash_acc_count <- renderText({
    df <- get_accusation_stats(conn)
    total_ents <- sum(df$unique_entities)
    paste0(total_ents, " unique accused entities")
  })

  output$dash_accused_table <- renderReactable({
    df <- get_top_accused(conn, 25)
    if (nrow(df) == 0) return(NULL)
    shared <- tolower(sm$shared_entities)
    df$corroborated <- tolower(df$entity_value) %in% shared
    df$corroborated_label <- ifelse(df$corroborated, "\u2705 Corroborated", "\u274c Testimony only")
    df$entity_type <- tools::toTitleCase(gsub("_", " ", df$entity_type))
    reactable(df[, c("entity_value", "entity_type", "mentions", "witnesses", "corroborated_label")],
      columns = list(
        entity_value = colDef(name = "Entity", minWidth = 180),
        entity_type = colDef(name = "Type", width = 120),
        mentions = colDef(name = "Mentions", width = 90),
        witnesses = colDef(name = "Witnesses", width = 90),
        corroborated_label = colDef(name = "Status", width = 160)
      ),
      defaultPageSize = 15, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  output$dash_mentioned_table <- renderReactable({
    top <- net$stats$top_mentioned
    if (is.null(top) || length(top) == 0) return(NULL)
    df <- do.call(rbind, lapply(top, as.data.frame, stringsAsFactors = FALSE))
    reactable(df, columns = list(
      name = colDef(name = "Witness", minWidth = 220),
      count = colDef(name = "Times Mentioned", width = 140,
        style = function(value) list(fontWeight = "bold", color = if (value > 500) "#e74c3c" else if (value > 100) "#f39c12" else "#ecf0f1"))
    ), defaultPageSize = 10, compact = TRUE, bordered = TRUE,
    theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
      borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  output$dash_reliability_table <- renderReactable({
    top <- net$stats$top_reliable
    if (is.null(top) || length(top) == 0) return(NULL)
    df <- do.call(rbind, lapply(top, as.data.frame, stringsAsFactors = FALSE))
    df$rel <- paste0(df$reliability, "%")
    df$corr <- paste0(df$corroborated, "/", df$total_entities)
    reactable(df[, c("name", "rel", "corr")],
      columns = list(
        name = colDef(name = "Witness", minWidth = 220),
        rel = colDef(name = "Reliability", width = 100,
          style = function(value) {
            v <- as.numeric(sub("%", "", value))
            color <- if (v >= 80) "#27ae60" else if (v >= 50) "#f39c12" else "#e74c3c"
            list(fontWeight = "bold", color = color)
          }),
        corr = colDef(name = "Corroborated", width = 130)
      ), defaultPageSize = 10, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  output$dash_validity_pct <- renderText({
    shared <- sm$stats$total_shared_entities
    acc_stats <- get_accusation_stats(conn)
    total_ents <- sum(acc_stats$unique_entities)
    if (total_ents == 0) return("0%")
    paste0(round(shared / total_ents * 100), "%")
  })

  output$dash_validity_detail <- renderText({
    shared <- sm$stats$total_shared_entities
    acc_stats <- get_accusation_stats(conn)
    total_ents <- sum(acc_stats$unique_entities)
    paste0(shared, " of ", total_ents, " accused entities have both documentary evidence and witness testimony support")
  })

  output$dash_validity_table <- renderReactable({
    df <- get_top_accused(conn, 25)
    if (nrow(df) == 0) return(NULL)
    shared <- tolower(sm$shared_entities)
    df$corroborated <- tolower(df$entity_value) %in% shared
    df$entity_type <- tools::toTitleCase(gsub("_", " ", df$entity_type))
    summ <- as.data.frame(
      aggregate(corroborated ~ entity_type, data = df, FUN = sum)
    )
    names(summ) <- c("Type", "Corroborated")
    total_per_type <- as.data.frame(
      aggregate(corroborated ~ entity_type, data = df, FUN = length)
    )
    summ$Total <- total_per_type$corroborated
    summ$Pct <- ifelse(summ$Total > 0, round(summ$Corroborated / summ$Total * 100), 0)
    summ$Rate <- paste0(summ$Corroborated, "/", summ$Total, " (", summ$Pct, "%)")
    reactable(summ[, c("Type", "Rate")],
      columns = list(
        Type = colDef(name = "Entity Type", width = 150),
        Rate = colDef(name = "Corroboration Rate", minWidth = 200)
      ),
      defaultPageSize = 10, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  output$dash_accusations_table <- renderReactable({
    acc <- net$stats$top_accusations
    if (is.null(acc) || length(acc) == 0) return(NULL)
    df <- do.call(rbind, lapply(acc, as.data.frame, stringsAsFactors = FALSE))
    df$accused <- paste0(df$accuser, " \u2192 ", df$entity)

    # Severity keywords
    txt <- tolower(df$snippet %||% df$entity)
    sev_critical <- grepl("murder|kill|death|threat|violence|assassin|fatal|shoot|killed|died", txt)
    sev_high <- grepl("bribe|brib|fraud|stolen|theft|embezzle|kickback|payoff|corrupt", txt)
    sev_medium <- grepl("leak|cover.?up|obstruct|conspiracy|conceal|suppress|hide|secret", txt)

    df$severity <- ifelse(sev_critical, "Critical",
                    ifelse(sev_high, "High",
                    ifelse(sev_medium, "Medium", "Low")))

    # Extract the matched keyword per row
    df$kw <- ""
    df$kw[sev_critical] <- regmatches(txt[sev_critical],
      regexpr("murder|kill|death|threat|violence|assassin|fatal|shoot|killed|died", txt[sev_critical]))
    df$kw[sev_high] <- regmatches(txt[sev_high],
      regexpr("bribe|brib|fraud|stolen|theft|embezzle|kickback|payoff|corrupt", txt[sev_high]))
    df$kw[sev_medium] <- regmatches(txt[sev_medium],
      regexpr("leak|cover.?up|obstruct|conspiracy|conceal|suppress|hide|secret", txt[sev_medium]))

    # Build accusation: keyword prefix + snippet + hover tooltip
    kw_label <- ifelse(nzchar(df$kw),
      paste0(toupper(substr(df$kw, 1, 1)), substr(df$kw, 2, nchar(df$kw)), ": "), "")
    has_snip <- nzchar(df$snippet)
    acc_text <- ifelse(has_snip,
      paste0("\"", substr(df$snippet, 1, 100),
             ifelse(nchar(df$snippet) > 100, "...\"", "\""),
             " (Day ", df$day, ")"),
      paste0(df$entity, " (", df$entityType, ")"))
    src_label <- ifelse(df$evidenceBacked %||% FALSE,
      "Source: EVIDENCE", "Source: TESTIMONY")
    hover_detail <- paste0(df$severity, " | Keyword: ", df$kw, " | ", src_label)
    df$accusation <- paste0(
      "<span title='", htmltools::htmlEscape(hover_detail), "'>",
      htmltools::htmlEscape(paste0(kw_label, acc_text)),
      "</span>"
    )

    sev_colors <- c(Critical = "#e74c3c", High = "#e67e22", Medium = "#f1c40f", Low = "#95a5a6")

    sev_badge <- paste0(
      "<span title='", htmltools::htmlEscape(src_label), "' ",
      "style='display:inline-block;width:10px;height:10px;border-radius:50%;",
      "background:", sev_colors[df$severity], ";margin-right:4px;'></span>",
      "<span title='", htmltools::htmlEscape(src_label), "'>",
      df$severity, "</span>"
    )

    reactable(cbind(data.frame(sev = sev_badge), df),
      columns = list(
        sev = colDef(name = "Severity", width = 100, html = TRUE),
        accusation = colDef(name = "Accusation", minWidth = 270, html = TRUE),
        accused = colDef(name = "Accused", minWidth = 210),
        severity = colDef(show = FALSE),
        snippet = colDef(show = FALSE),
        accuser = colDef(show = FALSE),
        entity = colDef(show = FALSE),
        entityType = colDef(show = FALSE),
        mentions = colDef(show = FALSE),
        day = colDef(show = FALSE),
                evidenceBacked = colDef(show = FALSE),
                source = colDef(show = FALSE),
                kw = colDef(show = FALSE),
    corroborators = colDef(name = "Corroborations", width = 130,
          style = function(value) {
            color <- if (value >= 5) "#27ae60"
                     else if (value >= 2) "#f39c12"
                     else "#e74c3c"
            list(fontWeight = "bold", color = color)
          }),
        score = colDef(name = "Strength Score", width = 120,
          style = function(value) {
            color <- if (value >= 5000) "#27ae60"
                     else if (value >= 1000) "#f39c12"
                     else "#e74c3c"
            list(fontWeight = "bold", color = color)
          })
      ),
      defaultPageSize = 20, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  # ── Overview Mini Network ────────────────────────────────────
  lighten_hex <- function(hex, by = 0.15) {
    hex <- sub("^#", "", hex)
    if (nchar(hex) != 6) return(paste0("#", hex))
    rgb <- c(
      strtoi(substr(hex,1,2), 16L),
      strtoi(substr(hex,3,4), 16L),
      strtoi(substr(hex,5,6), 16L)
    )
    rgb <- rgb + (255 - rgb) * by
    rgb <- pmin(rgb, 255)
    sprintf("#%02X%02X%02X", as.integer(rgb[1]), as.integer(rgb[2]), as.integer(rgb[3]))
  }

  output$overview_network <- renderVisNetwork({
    all_nodes <- net$nodes
    # Balanced selection: top 40 persons + top 40 entities
    p_nodes <- Filter(function(n) n$nodeType == "person", all_nodes)
    e_nodes <- Filter(function(n) n$nodeType == "entity", all_nodes)
    p_sorted <- p_nodes[order(sapply(p_nodes, `[[`, "value"), decreasing = TRUE)]
    e_sorted <- e_nodes[order(sapply(e_nodes, `[[`, "value"), decreasing = TRUE)]
    top_nodes <- c(p_sorted[1:min(40, length(p_sorted))],
                   e_sorted[1:min(40, length(e_sorted))])
    n_take <- length(top_nodes)
    if (n_take == 0) return(NULL)
    top_ids <- sapply(top_nodes, function(n) n$id)

    # Rank nodes by prominence to vary shade within each role
    top_nodes <- lapply(top_nodes, function(n) {
      n$.rank <- n$value  # segment count for ranking
      n
    })

    all_edges <- net$edges
    top_edges <- Filter(function(e) e$from %in% top_ids && e$to %in% top_ids, all_edges)
    n_edges <- min(300, length(top_edges))
    top_edges <- top_edges[1:n_edges]

    # Compute quantile thresholds for shade variation within each group
    grp_values <- sapply(top_nodes, function(n) n$group %||% "other")
    grp_segments <- split(sapply(top_nodes, `[[`, "value"), grp_values)
    grp_thresholds <- lapply(grp_segments, function(v) {
      if (length(v) < 3) return(c(Inf, Inf))
      quantile(v, probs = c(0.25, 0.75))
    })

    build_nodes_df <- function(nodes) {
      do.call(rbind, lapply(seq_along(nodes), function(i) {
        n <- nodes[[i]]
        grp <- n$group %||% "other"
        segs <- n$value
        bg <- n$color$background
        bd <- n$color$border
        hbg <- n$color$highlight$background
        hbd <- n$color$highlight$border
        # Vary shade: top 25% = original, middle 50% = lightened, bottom 25% = lightest
        th <- grp_thresholds[[grp]]
        if (length(th) == 2 && !is.na(th[2]) && is.finite(th[2])) {
          if (segs >= th[2]) {
            # top quartile — keep original
          } else if (segs >= th[1]) {
            bg <- lighten_hex(bg, 0.15)
            bd <- lighten_hex(bd, 0.15)
            hbg <- lighten_hex(hbg, 0.15)
          } else {
            bg <- lighten_hex(bg, 0.30)
            bd <- lighten_hex(bd, 0.30)
            hbg <- lighten_hex(hbg, 0.30)
          }
        }
        is_mkhwanazi <- grepl("Mkhwanazi", n$label)
          data.frame(
            id = n$id,
            label = n$label,
            origLabel = n$label,
            startLabel = if (is_mkhwanazi) n$label else "",
            labelSize = (n$font$size %||% 10) * 1.1,
            group = n$group,
            size = n$size * 0.7,
            baseSize = n$size * 0.7,
          fixed = n$fixed %||% FALSE,
          x = n$x %||% NA,
          y = n$y %||% NA,
          shape = "dot",
          font.size = if (is_mkhwanazi) (n$font$size %||% 10) * 1.1 else 0,
          font.color = "#FFFFFF",
          font.face = "Arial",
          font.strokeWidth = 3,
          font.strokeColor = "#0f0f1a",
          color.background = bg,
          color.border = bd,
          borderWidth = n$borderWidth %||% 1,
          color.highlight.background = hbg,
          color.highlight.border = hbd,
          stringsAsFactors = FALSE
        )
      }))
    }
    build_edges_df <- function(edges) {
      if (length(edges) == 0) return(data.frame(from = integer(), to = integer()))
      ef <- do.call(rbind, lapply(edges, function(e) {
          data.frame(
            from = e$from, to = e$to,
            width = e$width %||% 1,
            title = e$title %||% "",
            dashes = isTRUE(e$dashes %||% FALSE),
            color.color = e$color$color %||% "#3498db",
            color.opacity = e$color$opacity %||% 1,
            entityValue = e$entityValue %||% "",
            entityType = e$entityType %||% "",
            stringsAsFactors = FALSE
          )
      }))
      # Sort: entity-to-entity edges (both IDs negative) last so they render on top
      ef$is_ee <- ef$from < 0 & ef$to < 0
      ef[order(ef$is_ee), !names(ef) %in% "is_ee"]
    }

    nodes_pos <- build_nodes_df(top_nodes)
    visNetwork(nodes = nodes_pos,
               edges = build_edges_df(top_edges)) |>
      visNodes(font = list(size = 14, color = "#FFFFFF", face = "Arial",
               strokeWidth = 3, strokeColor = "#0f0f1a")) |>
      visEdges(smooth = FALSE) |>
      visInteraction(dragNodes = FALSE, dragView = TRUE, zoomView = TRUE) |>
      # TODO: Re-enable animated physics for interactive feel:
      # visPhysics(solver = "barnesHut", barnesHut = list(gravitationalConstant = -500,
      #   springLength = 250, springConstant = 0.005, damping = 0.5),
      #   stabilization = list(iterations = 50))
      visPhysics(enabled = FALSE) |>
      visEvents(click = "function(params) {
        var net = this;
        if (params.nodes.length > 0) {
          // ── Node clicked ──
          var selId = String(params.nodes[0]);
          Shiny.setInputValue('overview_selected', selId, {priority: 'event'});
          var connNodeIds = net.getConnectedNodes(selId).map(String);
          var connEdgeIds = net.getConnectedEdges(selId).map(String);

          var allNodeIds = net.body.data.nodes.getIds().map(String);
          var allEdgeIds = net.body.data.edges.getIds().map(String);

          // Edges: connected yellow, others dimmed
          var eBatch = [];
          for (var i = 0; i < allEdgeIds.length; i++) {
            eBatch.push({
              id: allEdgeIds[i],
              color: connEdgeIds.indexOf(allEdgeIds[i]) !== -1
                ? '#f1c40f' : {color: '#3498db', opacity: 0.12},
              width: connEdgeIds.indexOf(allEdgeIds[i]) !== -1 ? 3 : 1
            });
          }
          net.body.data.edges.update(eBatch);

          // Nodes: connected enlarge 1.5x, labels only for clicked node
          var nBatch = [];
          for (var i = 0; i < allNodeIds.length; i++) {
            var d = net.body.data.nodes.get(allNodeIds[i]);
            nBatch.push({
              id: allNodeIds[i],
              size: connNodeIds.indexOf(allNodeIds[i]) !== -1
                ? d.baseSize * 1.5 : d.baseSize,
              'font.size': allNodeIds[i] === selId ? d.labelSize : 0
            });
          }
          net.body.data.nodes.update(nBatch);

        } else if (params.edges.length > 0) {
          // ── Edge clicked ──
          var d = net.body.data.edges.get(params.edges[0]);
          Shiny.setInputValue('overview_edge', {
            from: String(d.from), to: String(d.to),
            entityValue: d.entityValue || '',
            entityType: d.entityType || ''
          }, {priority: 'event'});

        } else {
          // ── Empty click (background) ── reset all
          var allNodeIds = net.body.data.nodes.getIds().map(String);
          var allEdgeIds = net.body.data.edges.getIds().map(String);

          var eBatch = [];
          for (var i = 0; i < allEdgeIds.length; i++) {
            eBatch.push({id: allEdgeIds[i], color: '#3498db', width: 1});
          }
          net.body.data.edges.update(eBatch);

          var nBatch = [];
          for (var i = 0; i < allNodeIds.length; i++) {
            var d = net.body.data.nodes.get(allNodeIds[i]);
            nBatch.push({id: allNodeIds[i], size: d.baseSize,
              'font.size': d.startLabel ? d.labelSize : 0});
          }
          net.body.data.nodes.update(nBatch);

          Shiny.setInputValue('overview_selected', null, {priority: 'event'});
          Shiny.setInputValue('overview_edge', null, {priority: 'event'});
        }
      }")
  })

  ent_expanded <- reactiveVal(FALSE)

  output$overview_entities <- renderUI({
    top <- net$top_entities
    show_all <- isTRUE(ent_expanded())
    if (!show_all) return(tags$p("Click 'Show All' to view entities", class = "text-muted"))
    tags <- lapply(top, function(e) {
      tags$span(class = "entity-tag",
                paste0(e$value, " (", e$count, ")"))
    })
    do.call(tagList, tags)
  })

  observeEvent(input$ent_toggle, {
    new <- !ent_expanded()
    ent_expanded(new)
    updateActionButton(session, "ent_toggle",
      label = if (new) "Hide" else "Show All")
  })

  observeEvent(input$legend_btn, {
    showModal(modalDialog(
      title = "Node Legend",
      tags$div(
        style = "display:flex; flex-direction:column; gap:8px;",
        tags$b("Persons"),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:16px; height:16px;
            background:#E74C3C; border:2px solid #C0392B; border-radius:50%;"),
          tags$span("Witness")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:16px; height:16px;
            background:#C0392B; border:2px solid #999999; border-radius:50%;"),
          tags$span("Protected Witness")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:16px; height:16px;
            background:#777777; border:2px solid #444444; border-radius:50%;"),
          tags$span("Mkhwanazi (Whistleblower)")),
        tags$hr(),
        tags$b("Case Entities (all grey)"),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:16px; height:16px;
            background:#999999; border:2px solid #666666; border-radius:50%;"),
                  tags$span("Organizations (SAPS, SSA, Carnilinx, Hawks...)")),
        tags$hr(),
        tags$p(class = "text-muted", style = "font-size:0.8rem;",
          "Darker shade = more frequent. Bigger node = more mentions.")
      ),
      easyClose = TRUE, size = "s",
      footer = modalButton("Close")
    ))
  })

  # ── Overview Detail Panel ───────────────────────────────────
  overview_detail_data <- reactive({
    sel <- input$overview_selected
    if (is.null(sel) || length(sel) == 0) return(NULL)
    sel <- as.character(sel)
    # Find node in net$nodes
    nd <- NULL
    for (n in net$nodes) {
      if (as.character(n$id) == sel) { nd <- n; break }
    }
    nd
  })

  overview_edge_data <- reactive({
    ed <- input$overview_edge
    if (is.null(ed) || is.null(ed$from)) return(NULL)
    ed
  })

  output$overview_detail_header <- renderText({
    nd <- overview_detail_data()
    ed <- overview_edge_data()
    if (!is.null(nd)) paste0(nd$label, " (", nd$nodeType, ")")
    else if (!is.null(ed)) paste0("Connection: Person \u2192 Entity")
    else "Click a node or edge to see case details"
  })

  output$overview_detail_panel <- renderUI({
    nd <- overview_detail_data()
    ed <- overview_edge_data()

    # Priority: edge click > node click
    if (!is.null(ed)) {
      from_id <- as.numeric(ed$from)
      to_id <- as.numeric(ed$to)
      # Find person name and entity value
      from_nm <- ""
      to_nm <- ed$entityValue %||% ""
      for (n in net$nodes) {
        if (n$id == from_id) from_nm <- n$label
      }
      # Query snippet
      snippets <- NULL
      tryCatch({
        sn <- get_entity_snippets(conn, from_id, to_nm, limit = 2)
        if (nrow(sn) > 0) snippets <- sn
      }, error = function(e) {})
      tagList(
        tags$p(tags$b("Accuser: "), from_nm),
        tags$p(tags$b("Accused entity: "), to_nm, " (", ed$entityType, ")"),
        if (!is.null(snippets) && nrow(snippets) > 0)
          tagList(tags$hr(), tags$b("Evidence excerpt:"),
            lapply(seq_len(nrow(snippets)), function(i) {
              tags$blockquote(style = "font-size:0.85rem; border-left:3px solid #3498db; padding-left:12px; margin:6px 0;",
                tags$small(class = "text-muted", paste0("Day ", snippets[i,"day_number"], " — ", snippets[i,"hearing_date"])),
                tags$br(),
                substr(snippets[i,"context_text"], 1, 400))
            }))
      )
    } else if (!is.null(nd)) {
      if (nd$nodeType == "person") {
        # Show entities this person named
        ents <- NULL
        tryCatch({
          ents <- get_person_entities(conn, nd$id)
        }, error = function(e) {})
        tagList(
          tags$p(tags$b("Role: "), nd$role, " | ",
                 tags$b("Segments: "), format(nd$segments, big.mark = ","), " | ",
                 tags$b("Days: "), nd$days),
          tags$p(tags$b("Entities named in testimony:")),
          if (!is.null(ents) && nrow(ents) > 0)
            tags$div(style = "display:flex; flex-wrap:wrap; gap:8px;",
              lapply(seq_len(min(nrow(ents), 15)), function(i) {
                tags$span(class = "entity-tag",
                  paste0(ents[i,"entity_value"], " (", ents[i,"cnt"], "x, ", ents[i,"entity_type"], ")"))
              }))
          else tags$p("No entity data found", class = "text-muted")
        )
      } else {
        # Entity node — show witnesses who named it
        wits <- NULL
        tryCatch({
          wits <- get_entity_witnesses(conn, nd$label)
        }, error = function(e) {})
        tagList(
          tags$p(tags$b("Type: "), nd$entityType, " | ",
                 tags$b("Total mentions: "), nd$mentionCount, " | ",
                 tags$b("Witnesses: "), nd$witnessCount),
          tags$p(tags$b("Witnesses who named this:")),
          if (!is.null(wits) && nrow(wits) > 0)
            tags$div(style = "display:flex; flex-wrap:wrap; gap:8px;",
              lapply(seq_len(min(nrow(wits), 15)), function(i) {
                tags$span(class = "entity-tag",
                  paste0(wits[i,"canonical_name"], " (", wits[i,"cnt"], "x, ", wits[i,"role"], ")"))
              }))
          else tags$p("No witness data found", class = "text-muted")
        )
      }
    } else {
      p("Click any person (green/red) to see what entities they named, or any entity (gold/blue/purple) to see who named it. Click an edge to see evidence.", class = "text-muted")
    }
  })

  # ── Connections Graph ────────────────────────────────────
  filtered_nodes <- reactive({
    edge_type <- input$conn_edge_type %||% "all"

    if (edge_type == "all") {
      nodes <- net$nodes
    } else {
      person_edges <- Filter(function(e) e$type == edge_type, net$person_edges %||% list())
      edge_from <- sapply(person_edges, `[[`, "from")
      edge_to <- sapply(person_edges, `[[`, "to")
      active_ids <- unique(c(edge_from, edge_to))
      nodes <- Filter(function(n) n$id %in% active_ids && n$nodeType == "person", net$nodes)
    }

    if (!is.null(input$net_roles)) {
      nodes <- Filter(function(n) n$role %in% input$net_roles, nodes)
    }
    if (input$net_min_edges > 0) {
      edge_from <- sapply(net$edges, `[[`, "from")
      edge_to <- sapply(net$edges, `[[`, "to")
      node_ids <- sapply(nodes, `[[`, "id")
      ids_with_edges <- unique(c(edge_from, edge_to))
      nodes <- Filter(function(n) {
        sum(edge_from == n$id | edge_to == n$id) >= input$net_min_edges
      }, nodes)
    }
    nodes
  })

  filtered_edges <- reactive({
    edge_type <- input$conn_edge_type %||% "all"
    node_ids <- sapply(filtered_nodes(), `[[`, "id")

    if (edge_type == "all") {
      Filter(function(e) e$from %in% node_ids && e$to %in% node_ids, net$edges)
    } else {
      person_edges <- Filter(function(e) e$type == edge_type, net$person_edges %||% list())
      Filter(function(e) e$from %in% node_ids && e$to %in% node_ids, person_edges)
    }
  })

  output$net_header <- renderText({
    edge_type <- input$conn_edge_type %||% "all"
    type_label <- switch(edge_type,
      all = "Case Web",
      questioning = "Questioning Patterns",
      co_testified = "Co-testified",
      mentions = "Mentions",
      edge_type)
    paste0(type_label, " — ", length(filtered_nodes()), " people, ",
           length(filtered_edges()), " connections")
  })

  output$network_graph <- renderVisNetwork({
    fn <- filtered_nodes()
    fe <- filtered_edges()
    if (length(fn) == 0) return(NULL)
    edge_type <- input$conn_edge_type %||% "all"

    # Edge color by type
    edge_color <- switch(edge_type,
      questioning = "#f39c12",
      co_testified = "#3498db",
      mentions = "#e74c3c",
      "#3498db")

    nodes_df <- do.call(rbind, lapply(fn, function(n) {
      data.frame(id = n$id, label = n$label, group = n$group,
                 value = n$value, size = n$size %||% 25,
                 color.background = n$color$background %||% "#999999",
                 color.border = n$color$border %||% "#666666",
                 color.highlight.background = n$color$highlight.background %||% "#BBBBBB",
                 color.highlight.border = n$color$highlight.border %||% "#666666",
                 shape = n$shape %||% "dot", font.size = n$font$size %||% 12,
                 stringsAsFactors = FALSE)
    }))

    edges_df <- if (length(fe) > 0) {
      do.call(rbind, lapply(fe, function(e) {
        if (edge_type == "all") {
          data.frame(from = e$from, to = e$to,
                     width = e$width %||% 1, title = e$title %||% "",
                     dashes = isTRUE(e$dashes %||% FALSE),
                     stringsAsFactors = FALSE)
        } else {
          data.frame(from = e$from, to = e$to,
                     value = e$weight %||% 1, width = 1 + (e$weight %||% 1) / 10,
                     title = paste0(e$type, " (", e$weight, "x)"),
                     color = edge_color,
                     stringsAsFactors = FALSE)
        }
      }))
    } else {
      data.frame(from = integer(), to = integer())
    }
    visNetwork(nodes_df, edges_df) |>
      visNodes(font = list(color = "#ecf0f1")) |>
      visEdges(smooth = FALSE, color = list(opacity = 0.4)) |>
      visOptions(
        highlightNearest = list(enabled = TRUE, degree = 2, hover = TRUE),
        selectedBy = list(variable = "group", multiple = TRUE)
      ) |>
      visInteraction(
        dragNodes = TRUE, dragView = TRUE, zoomView = TRUE,
        navigationButtons = TRUE
      ) |>
      # TODO: Re-enable animated physics for interactive feel:
      # visPhysics(solver = "barnesHut", barnesHut = list(gravitationalConstant = -500,
      #   springLength = 250, springConstant = 0.005, damping = 0.5),
      #   stabilization = list(iterations = 50))
      visPhysics(enabled = FALSE) |>
      visLayout(randomSeed = 42) |>
      visEvents(click = "function(data) {
        if (data.nodes.length > 0) {
          Shiny.setInputValue('net_selected', data.nodes[0], {priority: 'event'});
        } else {
          Shiny.setInputValue('net_selected', null, {priority: 'event'});
        }
      }")
  })

  observeEvent(input$net_reset, {
    session$sendCustomMessage("reset_network", list())
  })

  # ── Attention Map ────────────────────────────────────────────
  att_n <- reactive({
    min(input$att_top_n %||% 10, length(att[["questioners"]] %||% c()))
  })

  output$attention_heatmap <- renderPlotly({
    am <- att
    if (is.null(am) || length(am[["questioners"]]) == 0) {
      return(plotly_empty(type = "heatmap") |>
               layout(title = "No attention data available"))
    }

    n <- min(att_n(), am[["nrow"]] %||% 0)
    qs <- am[["questioners"]][1:n]

    # Reconstruct matrix from flat data
    mat <- matrix(am[["data"]], nrow = am[["nrow"]], ncol = am[["ncol"]], byrow = TRUE)
    mat <- mat[1:n, , drop = FALSE]
    ws <- am[["witnesses"]]

    # Only keep witnesses with at least one interaction
    col_sums <- colSums(mat)
    keep <- col_sums > 0
    ws <- ws[keep]
    mat <- mat[, keep, drop = FALSE]
    if (ncol(mat) == 0 || nrow(mat) == 0) {
      return(plotly_empty(type = "heatmap") |>
               layout(title = "No questioning interactions found"))
    }

    attention_mat <<- mat
    attention_qs <<- qs
    attention_ws <<- ws

    plot_ly(
      x = ws,
      y = qs,
      z = mat,
      type = "heatmap",
      colorscale = list(c(0, 0.3, 0.7, 1), c("#1a1a2e", "#3498db", "#f39c12", "#e74c3c")),
      hovertemplate = "<b>%{y}</b> questioned <b>%{x}</b><br>%{z} interactions<extra></extra>"
    ) |>
      layout(
        xaxis = list(title = "", tickangle = -45, tickfont = list(size = 9)),
        yaxis = list(title = "", tickfont = list(size = 9)),
        plot_bgcolor = "#16213e",
        paper_bgcolor = "#16213e",
        font = list(color = "#ecf0f1"),
        margin = list(l = 120, b = 120)
      ) |>
      event_register("plotly_click")
  })

  observeEvent(event_data("plotly_click", source = "attention_heatmap"), {
    click <- event_data("plotly_click", source = "attention_heatmap")
    if (is.null(click)) return()
    output$att_detail <- renderUI({
      w_idx <- click$x + 1
      q_idx <- click$y + 1
      if (q_idx > length(attention_qs) || w_idx > length(attention_ws)) return(NULL)
      q_name <- attention_qs[q_idx]
      w_name <- attention_ws[w_idx]
      val <- attention_mat[q_idx, w_idx]
      tagList(
        h6(paste0(q_name, " \u2192 ", w_name)),
        p(paste0(val, " direct questioning interactions"), class = "text-muted")
      )
    })
  })

  # ── Selected node info (Connections tab) ─────────────────────
  # Debug: show raw selected node ID
  output$net_debug <- renderText({
    paste0("Selected ID: ", input$net_selected %||% "(none)")
  })

  output$net_node_info <- renderUI({
    sel_id <- input$net_selected
    if (is.null(sel_id) || length(sel_id) == 0 || nchar(sel_id) == 0) {
      return(p("Click a node to see details", class = "text-muted"))
    }

    sel_id_num <- as.numeric(sel_id)

    # Search all nodes (not just filtered) to always find the clicked node
    node <- NULL
    for (n in net$nodes) {
      if (as.numeric(n$id) == sel_id_num) { node <- n; break }
    }
    if (is.null(node)) {
      return(p("Node not found", class = "text-muted"))
    }

    if (!is.null(node$nodeType) && node$nodeType == "entity") {
      tagList(
        h5(node$label),
        p(tags$b("Type: "), node$entityType %||% "entity"),
        p(tags$b("Mentions: "), format(node$value %||% 0, big.mark = ",")),
        p(tags$b("Witnesses named: "), node$witnessCount %||% 0)
      )
    } else {
      tagList(
        h5(node$label),
        p(tags$b("Role: "), node$role %||% ""),
        p(tags$b("Rank: "), node$rank %||% ""),
        p(tags$b("Segments: "), format(node$segments %||% 0, big.mark = ",")),
        p(tags$b("Hearing days: "), node$days %||% 0)
      )
    }
  })

  # ── Witnesses and Entities ──────────────────────────────────
  output$role_cards <- renderUI({
    roles_to_show <- if (input$roles_filter == "All") {
      names(net$roles)
    } else {
      input$roles_filter
    }

    cards <- lapply(roles_to_show, function(role) {
      members <- net$roles[[role]]
      if (is.null(members) || length(members) == 0) return(NULL)
      color <- ROLE_COLORS[[role]] %||% "#95a5a6"

      member_html <- lapply(members[1:min(20, length(members))], function(m) {
        tags$button(
          class = "role-card",
          onclick = sprintf("Shiny.setInputValue('selected_witness', '%s', {priority: 'event'})",
                            gsub("'", "\\\\'", m$name)),
          style = paste0("border-left-color: ", color,
                         "; background: rgba(255,255,255,0.03); width:100%; text-align:left; "
                         , "border: none; border-left: 4px solid ", color,
                         "; cursor: pointer; display: block;"),
          tags$strong(m$name),
          tags$br(),
          tags$small(paste0(m$rank, " · ", format(m$segments, big.mark = ","),
                            " segments · ", m$days, " days"))
        )
      })

      card(
        card_header(
          tags$span(style = paste0("color: ", color, ";"),
                    paste0(toupper(sub("_", " ", role)), "S"),
                    tags$small(paste0(" (", length(members), ")")))
        ),
        card_body(
          div(style = "display:flex; flex-direction:column; gap:4px;",
            do.call(tagList, member_html)
          ),
          if (length(members) > 20) p(paste0("... and ", length(members) - 20, " more"), class = "text-muted")
        )
      )
    })

    layout_column_wrap(width = "400px", do.call(tagList, cards[!sapply(cards, is.null)]))
  })

  selected_witness_name <- reactiveVal(NULL)

  observeEvent(input$selected_witness, {
    selected_witness_name(input$selected_witness)
  })

  output$witness_entity_detail <- renderUI({
    name <- selected_witness_name()
    if (is.null(name)) {
      return(tagList(
        h6("Click a witness to see details"),
        p("Entity profiles show what organizations, cases, locations and exhibits each witness named in testimony.", class = "text-muted")
      ))
    }

    # Find the speaker profile
    prof <- NULL
    prof_id <- NULL
    for (n in net$nodes) {
      if (n$nodeType == "person" && n$label == name) {
        prof_id <- as.character(n$id)
        break
      }
    }

    # Get entities from network data's speaker_profiles
    entities <- NULL
    if (!is.null(prof_id)) {
      prof_id_num <- as.numeric(prof_id)
      entities <- net$speaker_profiles[[as.character(prof_id_num)]]
      if (is.null(entities)) {
        # Try numeric key
        entities <- net$speaker_profiles[[prof_id_num]]
      }
    }

    # Also get from DB
    db_entities <- NULL
    if (!is.null(prof_id)) {
      tryCatch({
        db_entities <- get_person_entities(conn, as.numeric(prof_id), limit = 25)
      }, error = function(e) {})
    }

    # Prefer DB data
    display_ents <- db_entities
    if (is.null(display_ents) || nrow(display_ents) == 0) {
      if (!is.null(entities) && length(entities) > 0) {
        display_ents <- do.call(rbind, lapply(entities, function(e) {
          data.frame(entity_value = e$value, entity_type = e$type, cnt = e$count, stringsAsFactors = FALSE)
        }))
      }
    }

    tagList(
      h5(name),
      if (!is.null(display_ents) && nrow(display_ents) > 0) {
        tagList(
          p(tags$b("Entities named in testimony:"), style = "margin-bottom:4px;"),
          div(style = "display:flex; flex-direction:column; gap:4px;",
            lapply(seq_len(min(nrow(display_ents), 25)), function(i) {
              e <- display_ents[i, ]
              tags$div(
                style = "font-size:0.85rem; padding:4px 6px; border-radius:4px; background:rgba(255,255,255,0.03);",
                tags$span(style = "font-weight:bold;", e$entity_value),
                tags$span(style = "color:#888;font-size:0.75rem;", paste0(" (", e$entity_type, ", ", e$cnt, "x)"))
              )
            })
          )
        )
      } else {
        p("No entity data found for this witness.", class = "text-muted")
      },
      uiOutput("witness_prep_pack")
    )
  })

  # ── Timeline ─────────────────────────────────────────────────
  output$timeline_plot <- renderPlotly({
    h <- get_hearings(conn)
    if (nrow(h) == 0) return(NULL)
    h$hearing_date <- ymd(h$hearing_date)

    p <- ggplot(h, aes(x = hearing_date, y = 1, text = paste0("Day ", day_number))) +
      geom_point(aes(color = "Hearing"), size = 2.5, alpha = 0.8) +
      scale_x_date(date_breaks = "1 month", date_labels = "%b '%y") +
      scale_color_manual(values = c("Hearing" = "#3498db")) +
      labs(x = "", y = "", color = "") +
      theme_dark() +
      theme(
        axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        plot.background = element_rect(fill = "#16213e"),
        panel.background = element_rect(fill = "#16213e"),
        legend.position = "none"
      )

    ggplotly(p, tooltip = "text") |>
      layout(hovermode = "x", plot_bgcolor = "#16213e", paper_bgcolor = "#16213e",
             font = list(color = "#ecf0f1"))
  })

  output$timeline_table <- renderReactable({
    h <- get_hearings(conn)
    reactable(h[, c("day_number", "hearing_date", "summary")],
      columns = list(
        day_number = colDef(name = "Day", width = 60),
        hearing_date = colDef(name = "Date", width = 100),
        summary = colDef(name = "Summary", minWidth = 300)
      ),
      defaultPageSize = 25, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(
        backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")
      )
    )
  })

  # ── Search ───────────────────────────────────────────────────
  observe({
    spk <- get_speaker_stats(conn)
    choices <- setNames(spk$canonical_name, paste0(spk$canonical_name, " (", spk$role, ")"))
    updateSelectizeInput(session, "search_spk", choices = choices, server = TRUE)
  })

  sr <- reactive({
    req(input$search_q)
    search_fts(conn, input$search_q,
      date_from = if (!is.null(input$search_from)) as.character(input$search_from) else NULL,
      date_to   = if (!is.null(input$search_to))   as.character(input$search_to)   else NULL,
      speaker   = if (length(input$search_spk) > 0) input$search_spk[1] else NULL)
  }) |> bindEvent(input$search_q, input$search_from, input$search_to, input$search_spk)

  output$search_header <- renderText({
    if (is.null(input$search_q) || nzchar(input$search_q) == 0) return("Enter a query to search")
    paste0('Results for "', input$search_q, '" — ', nrow(sr()), " matches")
  })

  output$search_results <- renderReactable({
    req(input$search_q)
    df <- sr()
    if (nrow(df) == 0) return(NULL)
    reactable(df[, c("date", "speaker", "preview")],
      columns = list(
        date    = colDef(name = "Date", width = 100),
        speaker = colDef(name = "Speaker", width = 180),
        preview = colDef(name = "Text", minWidth = 350, html = TRUE)
      ),
      defaultPageSize = 20, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
    )
  })

  # ── Entities ─────────────────────────────────────────────────
  ent_data <- reactive({
    get_top_entities(conn, etype = "organization", limit = 50)
  })

  output$ent_list <- renderReactable({
    reactable(ent_data(),
      columns = list(
        entity_value = colDef(name = "Organization", minWidth = 180),
        cnt          = colDef(name = "Mentions", width = 90)
      ),
      defaultPageSize = 20, compact = TRUE, bordered = TRUE,
      selection = "single", onClick = "select",
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"),
        rowSelectedStyle = list(backgroundColor = "#3498db", color = "#ffffff"))
    )
  })

  selected_ent <- reactive({
    sel <- getReactableState("ent_list", "selected")
    if (is.null(sel)) return(NULL)
    ent_data()[sel, "entity_value"]
  })

  output$ent_header <- renderText({
    org <- selected_ent()
    if (is.null(org)) return("Select an organization from the list")
    paste0("Organization: ", org)
  })

  output$ent_detail <- renderUI({
    org <- selected_ent()
    if (is.null(org)) return(p("Select an organization to see details", class = "text-muted"))

    showNotification("Loading organization details...", id = "org_loading", type = "message", duration = NULL)
    on.exit(removeNotification("org_loading"), add = TRUE)

    wits <- get_org_detail_witnesses(conn, org)
    locs <- get_org_locations(conn, org, limit = 20)
    cases <- get_org_cases(conn, org, limit = 20)

    tagList(
      layout_columns(
        col_widths = c(4, 4, 4),
        value_box(title = "Witnesses", value = wits$witness_count, showcase = icon("users"),
          theme = "primary"),
        value_box(title = "Case References", value = wits$case_count, showcase = icon("book"),
          theme = "info"),
        value_box(title = "Locations", value = wits$location_count, showcase = icon("map-marker"),
          theme = "secondary")
      ),
      hr(),
      h6("Associated Locations"),
      reactable(locs,
        columns = list(
          location = colDef(name = "Location", minWidth = 160),
          witnesses = colDef(name = "Witnesses", width = 100)
        ),
        defaultPageSize = 10, compact = TRUE, bordered = TRUE,
        theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
          borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
      ),
      hr(),
      h6("Associated Cases"),
      reactable(cases,
        columns = list(
          case_ref = colDef(name = "Case Reference", minWidth = 200),
          witnesses = colDef(name = "Witnesses", width = 100)
        ),
        defaultPageSize = 10, compact = TRUE, bordered = TRUE,
        theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
          borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
      )
    )
  })

  # ── Story Map ─────────────────────────────────────────────────
  sm <- load_story_map()

  observe({
    ents <- sm$all_entities
    if (length(ents) == 0) ents <- sm$shared_entities
    updateSelectizeInput(session, "story_entity", choices = unique(ents), server = TRUE)
  })

  observe({
    wits <- sapply(sm$unique_witnesses, `[[`, "name")
    updateSelectizeInput(session, "story_witness", choices = wits, server = TRUE)
  })

  output$story_quick_entities <- renderUI({
    ents <- head(sm$shared_entities, 15)
    if (length(ents) == 0) return(p("No data loaded. Run build_story_map.py.", class = "text-muted"))
    tags <- lapply(ents, function(e) {
      tags$span(class = "entity-tag", e)
    })
    do.call(tagList, tags)
  })

  filtered_comm <- reactive({
    events <- sm$commission_timeline
    rd <- input$story_dates
    if (!is.null(rd)) {
      events <- Filter(function(e) {
        d <- e$date
        if (is.null(d) || !nzchar(d)) return(FALSE)
        d >= rd[1] && d <= rd[2]
      }, events)
    }
    if (length(input$story_entity) > 0) {
      ents <- tolower(input$story_entity)
      events <- Filter(function(e) {
        ev_ents <- tolower(unlist(e$entities))
        length(intersect(ents, ev_ents)) > 0
      }, events)
    }
    events
  })

  filtered_wit <- reactive({
    events <- sm$witness_timeline
    rd <- input$story_dates
    if (!is.null(rd)) {
      events <- Filter(function(e) {
        d <- e$date
        if (is.null(d) || !nzchar(d)) return(FALSE)
        d >= rd[1] && d <= rd[2]
      }, events)
    }
    if (length(input$story_witness) > 0) {
      wits <- input$story_witness
      events <- Filter(function(e) e$speaker %in% wits, events)
    }
    if (length(input$story_entity) > 0) {
      ents <- tolower(input$story_entity)
      events <- Filter(function(e) {
        ev_ents <- tolower(unlist(e$entities))
        length(intersect(ents, ev_ents)) > 0
      }, events)
    }
    events
  })

  output$story_comm_plot <- renderPlotly({
    events <- filtered_comm()
    if (length(events) == 0) {
      return(plotly_empty(type = "scatter", mode = "markers") |>
               layout(title = list(text = "No matching documents",
                                   font = list(color = "#95a5a6"))))
    }
    dates <- as.Date(sapply(events, `[[`, "date"))
    cats <- sapply(events, `[[`, "category")
    titles <- sapply(events, `[[`, "title")
    df <- data.frame(date = dates, category = cats, title = titles,
                     stringsAsFactors = FALSE)

    cat_colors <- c(ruling = "#f39c12", application = "#3498db",
                    media_statement = "#2ecc71", media = "#9b59b6",
                    statement = "#e74c3c")
    df$color <- cat_colors[df$category]; df$color[is.na(df$color)] <- "#95a5a6"

    p <- ggplot(df, aes(x = date, y = 0, text = title, color = category)) +
      geom_point(size = 3, alpha = 0.9) +
      scale_color_manual(values = cat_colors) +
      scale_x_date(date_breaks = "1 month", date_labels = "%b '%y") +
      labs(x = "", y = "", color = "") +
      theme_dark() +
      theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
            panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
            plot.background = element_rect(fill = "#16213e"),
            panel.background = element_rect(fill = "#16213e"),
            legend.position = "bottom", legend.text = element_text(size = 8))
    ggplotly(p, tooltip = "text") |>
      layout(plot_bgcolor = "#16213e", paper_bgcolor = "#16213e",
             font = list(color = "#ecf0f1"), legend = list(orientation = "h", y = -0.2))
  })

  output$story_wit_plot <- renderPlotly({
    events <- filtered_wit()
    if (length(events) == 0) {
      return(plotly_empty(type = "scatter", mode = "markers") |>
               layout(title = list(text = "No matching testimony",
                                   font = list(color = "#95a5a6"))))
    }
    dates <- as.Date(sapply(events, `[[`, "date"))
    speakers <- sapply(events, `[[`, "speaker")
    days <- sapply(events, `[[`, "day")
    roles <- sapply(events, `[[`, "role")
    df <- data.frame(date = dates, speaker = speakers, day = days, role = roles,
                     stringsAsFactors = FALSE)

    role_colors <- c(witness = "#2ecc71", witness_protected = "#e74c3c")
    df$color <- role_colors[df$role]; df$color[is.na(df$color)] <- "#95a5a6"

    p <- ggplot(df, aes(x = date, y = 0,
                        text = paste0("Day ", day, ": ", speaker),
                        color = role)) +
      geom_point(size = 3, alpha = 0.9) +
      scale_color_manual(values = role_colors,
                         labels = c("Witness", "Protected Witness")) +
      scale_x_date(date_breaks = "1 month", date_labels = "%b '%y") +
      labs(x = "", y = "", color = "") +
      theme_dark() +
      theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
            panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
            plot.background = element_rect(fill = "#16213e"),
            panel.background = element_rect(fill = "#16213e"),
            legend.position = "bottom", legend.text = element_text(size = 8))
    ggplotly(p, tooltip = "text") |>
      layout(plot_bgcolor = "#16213e", paper_bgcolor = "#16213e",
             font = list(color = "#ecf0f1"), legend = list(orientation = "h", y = -0.2))
  })

  output$story_comm_table <- renderReactable({
    events <- filtered_comm()
    if (length(events) == 0) return(NULL)
    df <- data.frame(
      Date = sapply(events, `[[`, "date"),
      Category = sapply(events, `[[`, "category_label"),
      Title = sapply(events, `[[`, "title"),
      stringsAsFactors = FALSE
    )
    reactable(df,
      columns = list(Date = colDef(width = 100), Category = colDef(width = 130),
                     Title = colDef(minWidth = 200)),
      defaultPageSize = 10, compact = TRUE, bordered = TRUE,
      selection = "single", onClick = "select",
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
    )
  })

  output$story_wit_table <- renderReactable({
    events <- filtered_wit()
    if (length(events) == 0) return(NULL)
    df <- data.frame(
      Day = sapply(events, `[[`, "day"),
      Date = sapply(events, `[[`, "date"),
      Witness = sapply(events, `[[`, "speaker"),
      stringsAsFactors = FALSE
    )
    reactable(df,
      columns = list(Day = colDef(width = 55), Date = colDef(width = 100),
                     Witness = colDef(minWidth = 180)),
      defaultPageSize = 10, compact = TRUE, bordered = TRUE,
      selection = "single", onClick = "select",
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
    )
  })

  selected_comm_ev <- reactive({
    sel <- getReactableState("story_comm_table", "selected")
    if (is.null(sel)) return(NULL)
    fc <- filtered_comm()
    if (sel > length(fc)) return(NULL)
    fc[[sel]]
  })

  selected_wit_ev <- reactive({
    sel <- getReactableState("story_wit_table", "selected")
    if (is.null(sel)) return(NULL)
    fw <- filtered_wit()
    if (sel > length(fw)) return(NULL)
    fw[[sel]]
  })

  output$story_detail_header <- renderText({
    if (!is.null(selected_comm_ev())) {
      paste0("Document: ", selected_comm_ev()$title)
    } else if (!is.null(selected_wit_ev())) {
      paste0("Testimony: Day ", selected_wit_ev()$day, " — ", selected_wit_ev()$speaker)
    } else {
      "Click an event to see details"
    }
  })

  output$story_detail_panel <- renderUI({
    ce <- selected_comm_ev()
    we <- selected_wit_ev()
    if (!is.null(ce)) {
      ents <- paste(unlist(ce$entities), collapse = ", ")
      fp <- ce$file_path %||% ""
      tagList(
        tags$p(tags$b("Date: "), ce$date),
        tags$p(tags$b("Category: "), ce$category_label),
        tags$p(tags$b("Title: "), ce$title),
        if (nzchar(ents)) tags$p(tags$b("Related: "), ents),
        if (nzchar(fp)) tags$p(tags$b("File: "), tags$code(fp))
      )
    } else if (!is.null(we)) {
      ents <- paste(unlist(we$entities), collapse = ", ")
      txt <- NULL
      tryCatch({
        segs <- get_witness_segments(conn, we$speaker)
        if (nrow(segs) > 0) txt <- head(segs$text, 3)
      }, error = function(e) {})
      tagList(
        tags$p(tags$b("Day: "), we$day, " | ", tags$b("Date: "), we$date),
        tags$p(tags$b("Speaker: "), we$speaker),
        tags$p(tags$b("Role: "), we$role),
        if (nzchar(we$summary %||% "")) tags$p(tags$b("Summary: "), we$summary),
        if (nzchar(ents)) tags$p(tags$b("Key entities: "), ents),
        if (!is.null(txt) && length(txt) > 0)
          tagList(tags$hr(), tags$b("Transcript excerpts:"),
                  lapply(txt, function(t) tags$blockquote(
                    style = "font-size:0.85rem; border-left: 3px solid #3498db; padding-left: 12px; margin: 8px 0;",
                    substr(t, 1, 500))))
      )
    } else {
      p("Select an event from either timeline to view details here.", class = "text-muted")
    }
  })

  # ── Evidence Compare ─────────────────────────────────────────
  observe({
    req(sm)
    ents <- sm$all_entities
    if (length(ents) == 0) ents <- sm$shared_entities
    updateSelectizeInput(session, "ec_entity", choices = unique(ents), server = TRUE)
  })

  ec_docs <- reactive({
    req(input$ec_entity)
    ent <- tolower(input$ec_entity)
    events <- sm$commission_timeline
    Filter(function(e) any(tolower(unlist(e$entities)) == ent), events)
  })

  ec_wit <- reactive({
    req(input$ec_entity)
    get_entity_mentions(conn, input$ec_entity)
  })

  output$ec_summary <- renderUI({
    nd <- length(ec_docs())
    nw <- if (is.null(ec_wit())) 0 else nrow(ec_wit())
    tagList(
      tags$p(tags$b("Entity: "), input$ec_entity),
      tags$p(nd, " documents, ", nw, " testimony mentions")
    )
  })

  output$ec_docs_table <- renderReactable({
    events <- ec_docs()
    if (length(events) == 0) return(NULL)
    df <- data.frame(
      Date = sapply(events, `[[`, "date"),
      Type = sapply(events, `[[`, "category_label"),
      Title = sapply(events, `[[`, "title"),
      stringsAsFactors = FALSE
    )
    reactable(df, columns = list(
      Date = colDef(width = 100), Type = colDef(width = 120),
      Title = colDef(minWidth = 200)
    ), defaultPageSize = 8, compact = TRUE, bordered = TRUE,
    selection = "single", onClick = "select",
    theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
      borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  output$ec_wit_table <- renderReactable({
    df <- ec_wit()
    if (is.null(df) || nrow(df) == 0) return(NULL)
    df$ctx <- substr(df$context_text, 1, 200)
    df$day_ref <- paste0("Day ", df$day_number)
    reactable(df[, c("hearing_date", "day_ref", "speaker", "speaker_role", "ctx")],
      columns = list(
        hearing_date = colDef(name = "Date", width = 90),
        day_ref      = colDef(name = "Day", width = 60),
        speaker = colDef(name = "Witness", width = 160),
        speaker_role = colDef(name = "Role", width = 100),
        ctx = colDef(name = "Context", minWidth = 200)
      ), defaultPageSize = 8, compact = TRUE, bordered = TRUE,
      selection = "single", onClick = "select",
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  sel_ec_doc <- reactive({
    sel <- getReactableState("ec_docs_table", "selected")
    if (is.null(sel)) return(NULL)
    ev <- ec_docs(); if (sel > length(ev)) return(NULL); ev[[sel]]
  })

  sel_ec_wit <- reactive({
    sel <- getReactableState("ec_wit_table", "selected")
    if (is.null(sel)) return(NULL)
    df <- ec_wit(); if (sel > nrow(df)) return(NULL); df[sel, ]
  })

  output$ec_detail_header <- renderText({
    if (!is.null(sel_ec_doc())) paste0("Document: ", sel_ec_doc()$title)
    else if (!is.null(sel_ec_wit())) paste0("Testimony by ", sel_ec_wit()$speaker)
    else "Click a row to see full context"
  })

  output$ec_detail_panel <- renderUI({
    doc <- sel_ec_doc(); wit <- sel_ec_wit()
    if (!is.null(doc)) {
      tagList(
        tags$p(tags$b("Date: "), doc$date),
        tags$p(tags$b("Type: "), doc$category_label),
        tags$p(tags$b("Title: "), doc$title)
      )
    } else if (!is.null(wit)) {
      tagList(
        tags$p(tags$b("Speaker: "), wit$speaker, " (", wit$speaker_role, ")"),
        tags$p(tags$b("Date: "), wit$hearing_date, " | Day ", wit$day_number),
        tags$p(tags$b("Entity: "), wit$entity_value, " (", wit$entity_type, ")"),
        tags$hr(),
        tags$b("Context:"),
        tags$blockquote(style = "font-size:0.9rem; border-left:3px solid #3498db; padding-left:12px; margin:8px 0;",
          wit$context_text)
      )
    } else {
      p("Click a row to see full context and source.", class = "text-muted")
    }
  })

  # ── Premium: Evidence Bundle Export ────────────────────────────
  output$ec_bundle_button <- renderUI({
    req(input$ec_entity)
    if (LICENSE$tier == "starter") {
      div(style = "text-align:center; padding:8px;",
        tags$small(class = "text-muted",
          icon("lock"), " Evidence Bundle available on ",
          tags$strong("Professional"), " tier")
      )
    } else {
      actionButton("generate_bundle", "Generate Evidence Bundle",
        icon = icon("file-alt"), class = "btn-success btn-sm",
        width = "100%")
    }
  })

  observeEvent(input$generate_bundle, {
    req(input$ec_entity)
    html <- generate_bundle_html(conn, input$ec_entity, input$ec_type)
    if (is.null(html)) {
      showNotification("No data to generate bundle.", type = "warning")
      return()
    }
    tmp <- file.path(tempdir(), paste0("evidence_bundle_", gsub("[^A-Za-z0-9]", "_", input$ec_entity), ".html"))
    writeLines(html, tmp)
    showNotification("Evidence bundle generated! Opening in browser...", type = "success", duration = 5)
    browseURL(tmp)
  })

  # ── Premium: Witness Preparation Pack ──────────────────────────
  output$witness_prep_pack <- renderUI({
    name <- selected_witness_name()
    if (is.null(name)) return(NULL)
    if (LICENSE$tier == "starter") {
      div(style = "text-align:center; padding:8px; margin-top:8px;",
        tags$small(class = "text-muted",
          icon("lock"), " Witness Prep Pack available on ",
          tags$strong("Professional"), " tier")
      )
    } else {
      actionButton("show_prep_pack", "Witness Preparation Pack",
        icon = icon("user-graduate"), class = "btn-info btn-sm",
        width = "100%")
    }
  })

  observeEvent(input$show_prep_pack, {
    name <- selected_witness_name()
    if (is.null(name)) return()
    hearings <- get_witness_hearings(conn, name)
    entities <- tryCatch(get_person_entities(conn, as.numeric(input$overview_selected)), error = function(e) NULL)
    questioners <- tryCatch(get_witness_questioners(conn, name), error = function(e) NULL)
    segs <- tryCatch(get_witness_segments(conn, name), error = function(e) NULL)

    showModal(modalDialog(
      title = div(icon("user-graduate"), " Witness Preparation Pack: ", name),
      size = "l",
      easyClose = TRUE,
      fade = FALSE,
      tagList(
        layout_columns(
          col_widths = c(4, 4, 4),
          div(class = "stat-card", style = "background:#1a3a5c; border-radius:8px; padding:15px;",
            h2(style = "margin:0;color:#3498db;", nrow(hearings)),
            p(style = "margin:0;font-size:0.75rem;text-transform:uppercase;opacity:0.7;", "Days Testified")),
          div(class = "stat-card", style = "background:#1a3a5c; border-radius:8px; padding:15px;",
            h2(style = "margin:0;color:#27ae60;", if (!is.null(entities)) nrow(entities) else 0),
            p(style = "margin:0;font-size:0.75rem;text-transform:uppercase;opacity:0.7;", "Entities Named")),
          div(class = "stat-card", style = "background:#1a3a5c; border-radius:8px; padding:15px;",
            h2(style = "margin:0;color:#f39c12;", if (!is.null(segs)) nrow(segs) else 0),
            p(style = "margin:0;font-size:0.75rem;text-transform:uppercase;opacity:0.7;", "Testimony Segments"))
        ),
        hr(),
        if (!is.null(questioners) && nrow(questioners) > 0) tagList(
          h5("Who Questioned This Witness"),
          reactable(questioners, columns = list(
            questioner = colDef(name = "Questioner", minWidth = 200),
            interactions = colDef(name = "Interactions", width = 120)
          ), defaultPageSize = 10, compact = TRUE, bordered = TRUE,
          theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
            borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
        ),
        if (!is.null(entities) && nrow(entities) > 0) tagList(
          h5("Top Entities Named"),
          reactable(entities, columns = list(
            entity_value = colDef(name = "Entity", minWidth = 200),
            entity_type = colDef(name = "Type", width = 120),
            cnt = colDef(name = "Times", width = 80)
          ), defaultPageSize = 10, compact = TRUE, bordered = TRUE,
          theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
            borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
        ),
        if (!is.null(hearings) && nrow(hearings) > 0) tagList(
          h5("Hearing Dates"),
          reactable(hearings[, c("day_number", "hearing_date", "summary")], columns = list(
            day_number = colDef(name = "Day", width = 60),
            hearing_date = colDef(name = "Date", width = 100),
            summary = colDef(name = "Summary", minWidth = 250)
          ), defaultPageSize = 8, compact = TRUE, bordered = TRUE,
          theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
            borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
        )
      ),
      footer = modalButton("Close")
    ))
  })

  # ── Premium: Contradiction Engine ──────────────────────────────
  contradiction_data <- reactive({
    etype <- if (input$contradiction_type == "All") NULL else input$contradiction_type
    get_contradiction_candidates(conn, min_witnesses = input$contradiction_min_wit)
  })

  output$contradiction_list_header <- renderText({
    df <- contradiction_data()
    if (is.null(df) || nrow(df) == 0) return("No entities with multiple witnesses")
    paste0("Entities mentioned by 2+ witnesses (", nrow(df), " found)")
  })

  output$contradiction_list <- renderReactable({
    df <- contradiction_data()
    if (is.null(df) || nrow(df) == 0) return(NULL)
    reactable(df, columns = list(
      entity_value = colDef(name = "Entity", minWidth = 200),
      entity_type = colDef(name = "Type", width = 100),
      witness_count = colDef(name = "Witnesses", width = 90,
        style = function(v) list(fontWeight = "bold",
          color = if (v >= 5) "#e74c3c" else if (v >= 3) "#f39c12" else "#ecf0f1")),
      total_mentions = colDef(name = "Mentions", width = 90)
    ), defaultPageSize = 20, compact = TRUE, bordered = TRUE,
    selection = "single", onClick = "select",
    theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
      borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
  })

  selected_contradiction <- reactive({
    sel <- getReactableState("contradiction_list", "selected")
    if (is.null(sel)) return(NULL)
    df <- contradiction_data()
    if (sel > nrow(df)) return(NULL)
    df[sel, ]
  })

  output$contradiction_detail_header <- renderText({
    sel <- selected_contradiction()
    if (is.null(sel)) return("Select an entity to compare witness statements")
    paste0("Comparing statements about: ", sel$entity_value)
  })

  output$contradiction_summary <- renderUI({
    sel <- selected_contradiction()
    if (is.null(sel)) return(p("Select an entity from the list", class = "text-muted"))
    tagList(
      p(tags$b("Entity: "), sel$entity_value),
      p(tags$b("Type: "), sel$entity_type),
      p(tags$b("Witnesses: "), sel$witness_count),
      p(tags$b("Total mentions: "), sel$total_mentions)
    )
  })

  output$contradiction_detail <- renderUI({
    sel <- selected_contradiction()
    if (is.null(sel)) return(p("Select an entity to see side-by-side witness statements.", class = "text-muted"))

    by_witness <- get_entity_by_witness(conn, sel$entity_value)
    if (is.null(by_witness) || nrow(by_witness) == 0) {
      return(p("No detailed data available.", class = "text-muted"))
    }

    witnesses <- unique(by_witness$witness)
    cards <- lapply(witnesses, function(w) {
      w_data <- by_witness[by_witness$witness == w, ]
      card(
        card_header(span(style = "color:#e74c3c;font-weight:bold;", icon("user"), " ", w)),
        card_body(
          reactable(w_data[, c("hearing_date", "day_number", "context_text")], columns = list(
            hearing_date = colDef(name = "Date", width = 100),
            day_number = colDef(name = "Day", width = 60),
            context_text = colDef(name = "Statement", minWidth = 350)
          ), defaultPageSize = 5, compact = TRUE, bordered = TRUE,
          theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
            borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e")))
        )
      )
    })
    do.call(tagList, cards)
  })
}

shinyApp(ui, server)
