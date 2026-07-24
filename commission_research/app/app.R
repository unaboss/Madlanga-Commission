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

# ── UI ──────────────────────────────────────────────────────────
ui <- page_navbar(
  title = tags$span(
    tags$img(src = "", style = "display:none"),
    "Commission Research"
  ),
  theme = DARK_THEME,
  id = "nav",
  header = tagList(
    tags$head(
      tags$style(HTML("
      .stat-card { text-align: center; padding: 20px 10px; border-radius: 8px; }
      .stat-card h2 { font-size: 2rem; margin: 5px 0; font-weight: 700; }
      .stat-card p { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 1px; opacity: 0.7; margin: 0; }
      .role-card { border-left: 4px solid; padding: 12px; margin-bottom: 8px; border-radius: 4px; font-size: 0.85rem; }
      .role-card strong { font-size: 1rem; }
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

  # ── Network Graph ────────────────────────────────────────────
  nav_panel(
    title = "Network",
    layout_sidebar(
      sidebar = sidebar(
        width = 280,
        h6("Filter Nodes"),
        checkboxGroupInput("net_roles", "Show roles:",
          choices = names(ROLE_COLORS),
          selected = names(ROLE_COLORS)
        ),
        sliderInput("net_min_edges", "Min connections:", 0, 100, 0, step = 5),
        hr(),
        h6("Selected Node"),
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

  # ── Role Groupings ───────────────────────────────────────────
  nav_panel(
    title = "Roles",
    layout_sidebar(
      sidebar = sidebar(
        width = 250,
        h6("Role Categories"),
        selectInput("roles_filter", NULL,
          choices = c("All", names(ROLE_COLORS)),
          selected = "All"
        )
      ),
      uiOutput("role_cards")
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
        selectInput("ent_type", "Entity Type",
          choices = c("All", "organization", "case_reference", "exhibit",
                      "date", "location", "money", "vehicle"),
          selected = "All"),
        hr(),
        h6("Top Entities"),
        reactableOutput("ent_list")
      ),
      card(
        full_screen = TRUE,
        card_header(textOutput("ent_header")),
        card_body(reactableOutput("ent_detail"))
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

  # ── Dashboard ─────────────────────────────────────────────────
  nav_panel(
    title = "Dashboard",
    layout_columns(
      col_widths = c(2, 2, 2, 2, 2, 2),
      card(
        class = "stat-card",
        style = "border-top: 3px solid #3498db;",
        card_body(
          h2(textOutput("dash_hearings", inline = TRUE)),
          p("Hearings")
        )
      ),
      card(
        class = "stat-card",
        style = "border-top: 3px solid #27ae60;",
        card_body(
          h2(textOutput("dash_witnesses", inline = TRUE)),
          p("Witnesses")
        )
      ),
      card(
        class = "stat-card",
        style = "border-top: 3px solid #f39c12;",
        card_body(
          h2(textOutput("dash_segments", inline = TRUE)),
          p("Segments")
        )
      ),
      card(
        class = "stat-card",
        style = "border-top: 3px solid #8e44ad;",
        card_body(
          h2(textOutput("dash_documents", inline = TRUE)),
          p("Documents")
        )
      ),
      card(
        class = "stat-card",
        style = "border-top: 3px solid #e74c3c;",
        card_body(
          h2(textOutput("dash_accusations", inline = TRUE)),
          p("Accusations")
        )
      ),
      card(
        class = "stat-card",
        style = "border-top: 3px solid #1abc9c;",
        card_body(
          h2(textOutput("dash_corroborated", inline = TRUE)),
          p("Corroborated")
        )
      )
    ),
    card(
      full_screen = TRUE,
      style = "min-height: 380px;",
      card_header(
        div(style = "display:flex; justify-content:space-between; align-items:center;",
          span("Top Accused Entities"),
          span(class = "text-muted", style = "font-size:0.8rem;", textOutput("dash_acc_count"))
        )
      ),
      card_body(reactableOutput("dash_accused_table"))
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
          label = if (is_mkhwanazi) n$label else "",
          origLabel = n$label,
          startLabel = if (is_mkhwanazi) n$label else "",
          group = n$group,
          value = n$value, size = n$size * 0.7,
          baseSize = n$size * 0.7,
          fixed = n$fixed %||% FALSE,
          x = n$x %||% NA,
          y = n$y %||% NA,
          shape = "dot",
          font.size = (n$font$size %||% 10) * 1.1,
          font.color = "#FFFFFF",
          font.face = "Arial",
          font.strokeWidth = 3,
          font.strokeColor = "#0f0f1a",
          color.background = bg,
          color.border = bd,
          color.highlight.background = hbg,
          color.highlight.border = hbd,
          stringsAsFactors = FALSE
        )
      }))
    }
    build_edges_df <- function(edges) {
      if (length(edges) == 0) return(data.frame(from = integer(), to = integer()))
      do.call(rbind, lapply(edges, function(e) {
          data.frame(
            from = e$from, to = e$to, value = e$value,
            width = e$width %||% 1,
            title = e$title %||% "",
            dashes = isTRUE(e$dashes %||% FALSE),
            stringsAsFactors = FALSE
          )
      }))
    }

    visNetwork(nodes = build_nodes_df(top_nodes),
               edges = build_edges_df(top_edges)) |>
      visNodes(font = list(size = 14, color = "#FFFFFF", face = "Arial",
               strokeWidth = 3, strokeColor = "#0f0f1a")) |>
      visEdges(smooth = list(type = "curvedCW", roundness = 0.2),
               color = list(color = "#3498db", opacity = 1)) |>
      visInteraction(dragNodes = FALSE, dragView = TRUE, zoomView = TRUE) |>
      visPhysics(solver = "barnesHut", stabilization = list(enabled = TRUE, iterations = 80),
                 barnesHut = list(gravitationalConstant = -1000, springLength = 300,
                                  springConstant = 0.0008, damping = 0.12)) |>
      visEvents(selectNode = "function(params) {
        var net = this;
        var selId = params.nodes[0];
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
            label: allNodeIds[i] === selId ? d.origLabel : ''
          });
        }
        net.body.data.nodes.update(nBatch);
      }",
      deselectNode = "function() {
        var net = this;
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
          nBatch.push({id: allNodeIds[i], size: d.baseSize, label: d.startLabel});
        }
        net.body.data.nodes.update(nBatch);
      }",
      click = "function(params) {
        if (params.nodes.length === 0 && params.edges.length === 0) {
          var net = this;
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
            nBatch.push({id: allNodeIds[i], size: d.baseSize, label: d.startLabel});
          }
          net.body.data.nodes.update(nBatch);
          Shiny.setInputValue('overview_selected', null, {priority: 'event'});
          Shiny.setInputValue('overview_edge', null, {priority: 'event'});
        }
      }",
      select = "function(params) {
        if (params.nodes.length > 0) {
          Shiny.setInputValue('overview_selected', params.nodes[0], {priority: 'event'});
        }
      }",
      selectEdge = "function(params) {
        if (params.edges.length > 0) {
          var d = this.body.data.edges.get(params.edges[0]);
          Shiny.setInputValue('overview_edge', {
            from: String(d.from), to: String(d.to),
            entityValue: d.entityValue || '',
            entityType: d.entityType || ''
          }, {priority: 'event'});
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
            background:#90EE90; border:2px solid #228B22; border-radius:50%;"),
          tags$span("Witness")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:16px; height:16px;
            background:#FF6347; border:2px solid #8B0000; border-radius:50%;"),
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
          tags$span("Organization, Case, Exhibit, Location, Money")),
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

  # ── Full Network Graph ───────────────────────────────────────
  filtered_nodes <- reactive({
    nodes <- net$nodes
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
    node_ids <- sapply(filtered_nodes(), `[[`, "id")
    Filter(function(e) e$from %in% node_ids && e$to %in% node_ids, net$edges)
  })

  output$net_header <- renderText({
    paste0("Interaction Network — ", length(filtered_nodes()), " people, ",
           length(filtered_edges()), " connections")
  })

  output$network_graph <- renderVisNetwork({
    fn <- filtered_nodes()
    fe <- filtered_edges()
    if (length(fn) == 0) return(NULL)

    nodes_df <- do.call(rbind, lapply(fn, function(n) {
      data.frame(id = n$id, label = n$label, group = n$group,
                 value = n$value, size = n$size,
                 color.background = n$color$background,
                 color.border = n$color$border,
                 color.highlight.background = n$color$highlight$background,
                 color.highlight.border = n$color$highlight$border,
                 shape = n$shape, font.size = n$font$size,
                 stringsAsFactors = FALSE)
    }))

    edges_df <- if (length(fe) > 0) {
      do.call(rbind, lapply(fe, function(e) {
        data.frame(from = e$from, to = e$to, value = e$value,
                   width = e$width, title = e$title,
                   dashes = isTRUE(e$dashes %||% FALSE),
                   stringsAsFactors = FALSE)
      }))
    } else {
      data.frame(from = integer(), to = integer())
    }

    visNetwork(nodes_df, edges_df) |>
      visNodes(font = list(color = "#ecf0f1")) |>
      visEdges(smooth = list(type = "continuous"), color = list(opacity = 0.3)) |>
      visOptions(
        highlightNearest = list(enabled = TRUE, degree = 2, hover = TRUE),
        selectedBy = list(variable = "group", multiple = TRUE)
      ) |>
      visInteraction(
        dragNodes = TRUE, dragView = TRUE, zoomView = TRUE,
        navigationButtons = TRUE
      ) |>
      visPhysics(
        solver = "barnesHut",
        barnesHut = list(gravitationalConstant = -3000, springLength = 180,
                         springConstant = 0.01, damping = 0.2),
        stabilization = list(iterations = 300)
      ) |>
      visLayout(randomSeed = 42) |>
      visEvents(select = "function(data) {
        Shiny.setInputValue('net_selected', data.nodes[0], {priority: 'event'});
      }")
  })

  observeEvent(input$net_reset, {
    session$sendCustomMessage("reset_network", list())
  })

  # ── Selected node info ───────────────────────────────────────
  output$net_node_info <- renderUI({
    sel_id <- input$net_selected
    if (is.null(sel_id) || length(sel_id) == 0) return(p("Click a node to see details", class = "text-muted"))
    node <- Filter(function(n) n$id == sel_id, net$nodes)[[1]]
    if (is.null(node)) return(NULL)

    tagList(
      h5(node$label),
      p(tags$b("Role: "), node$role),
      p(tags$b("Rank: "), node$rank),
      p(tags$b("Segments: "), format(node$segments, big.mark = ",")),
      p(tags$b("Hearing days: "), node$days)
    )
  })

  # ── Role Groupings ───────────────────────────────────────────
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
        tags$div(class = "role-card",
          style = paste0("border-left-color: ", color, "; background: rgba(255,255,255,0.03);"),
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
        card_body(do.call(tagList, member_html),
          if (length(members) > 20) p(paste0("... and ", length(members) - 20, " more"), class = "text-muted")
        )
      )
    })

    layout_column_wrap(width = "400px", do.call(tagList, cards[!sapply(cards, is.null)]))
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
    et <- if (input$ent_type == "All") NULL else input$ent_type
    get_top_entities(conn, etype = et, limit = 30)
  })

  output$ent_list <- renderReactable({
    reactable(ent_data(),
      columns = list(
        entity_type  = colDef(name = "Type", width = 110),
        entity_value = colDef(name = "Entity", minWidth = 140),
        cnt          = colDef(name = "Count", width = 70)
      ),
      defaultPageSize = 15, compact = TRUE, bordered = TRUE,
      selection = "single", onClick = "select",
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
    )
  })

  selected_ent <- reactive({
    sel <- getReactableState("ent_list", "selected")
    if (is.null(sel)) return(NULL)
    ent_data()[sel, ]
  })

  output$ent_header <- renderText({
    se <- selected_ent()
    if (is.null(se)) return("Select an entity from the list")
    paste0("Entity: ", se$entity_value, " (", se$cnt, " mentions)")
  })

  output$ent_detail <- renderReactable({
    se <- selected_ent()
    if (is.null(se)) return(NULL)
    ctx <- get_entity_context(conn, se$entity_value, limit = 200)
    ctx$source_ref <- ifelse(ctx$source_type == "transcript",
      paste0("Day ", ctx$day_number),
      paste0(ctx$source_type, " (Day ", ctx$day_number, ")"))
    reactable(ctx[, c("hearing_date", "source_ref", "speaker", "context_text")],
      columns = list(
        hearing_date = colDef(name = "Date", width = 90),
        source_ref   = colDef(name = "Source", width = 85),
        speaker      = colDef(name = "Speaker", width = 180),
        context_text = colDef(name = "Context", minWidth = 350)
      ),
      defaultPageSize = 25, compact = TRUE, bordered = TRUE,
      theme = reactableTheme(backgroundColor = "#16213e", color = "#ecf0f1",
        borderColor = "#2c3e50", headerStyle = list(background = "#1a1a2e"))
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
}

shinyApp(ui, server)
