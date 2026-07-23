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
  secondary = "#2c3e50",
  success = "#27ae60",
  info = "#2980b9",
  warning = "#f39c12",
  danger = "#e74c3c",
  base_font = font_google("Inter"),
  heading_font = font_google("Inter"),
  "navbar-bg" = "#1a1a2e",
  "body-bg" = "#0f0f1a",
  "card-bg" = "#16213e",
  "card-cap-bg" = "#0f3460"
)

# ── Role colors ─────────────────────────────────────────────────
ROLE_COLORS <- c(
  commissioner      = "#FFD700",
  evidence_leader   = "#3498db",
  witness           = "#2ecc71",
  witness_protected = "#e74c3c",
  other             = "#95a5a6"
)

ROLE_ICONS <- c(
  commissioner      = "star",
  evidence_leader   = "scale-balanced",
  witness           = "user",
  witness_protected = "user-secret",
  other             = "circle-question"
)

# ── UI ──────────────────────────────────────────────────────────
ui <- page_navbar(
  title = tags$span(
    tags$img(src = "", style = "display:none"),
    "Commission Research"
  ),
  theme = DARK_THEME,
  id = "nav",
  header = tags$head(
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
    "))
  ),

  # ── Overview ─────────────────────────────────────────────────
  nav_panel(
    title = "Overview",
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      div(class = "stat-card",
        style = "background: linear-gradient(135deg, #1a3a5c, #2980b9);",
        p("Hearing Days"), h2(textOutput("stat_hearings", inline = TRUE))
      ),
      div(class = "stat-card",
        style = "background: linear-gradient(135deg, #1e5a3a, #27ae60);",
        p("Witnesses & Speakers"), h2(textOutput("stat_speakers", inline = TRUE))
      ),
      div(class = "stat-card",
        style = "background: linear-gradient(135deg, #5a3a1a, #f39c12);",
        p("Transcript Segments"), h2(textOutput("stat_segments", inline = TRUE))
      ),
      div(class = "stat-card",
        style = "background: linear-gradient(135deg, #3a1a5a, #8e44ad);",
        p("Extracted Entities"), h2(textOutput("stat_entities", inline = TRUE))
      )
    ),
    br(),
    layout_columns(
      col_widths = c(8, 4),
      card(
        full_screen = TRUE, style = "min-height: 450px;",
        card_header("Mini Network Map — Key Players"),
        card_body(visNetworkOutput("overview_network", height = "390px")),
        card_footer(
          div(style = "display:flex; justify-content:space-between; align-items:center;",
            actionButton("legend_btn", "Show Legend",
              class = "btn-sm btn-outline-secondary"),
            tags$small(class = "text-muted", "Hover to highlight connections")
          )
        )
      ),
      card(
        full_screen = TRUE, style = "min-height: 450px;",
        card_header("Top Entities"),
        card_body(uiOutput("overview_entities"))
      )
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
    n_take <- min(80, length(all_nodes))
    if (n_take == 0) return(NULL)
    top_nodes <- all_nodes[1:n_take]
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

    # Compute quantile thresholds for shade variation within each role
    role_segments <- split(sapply(top_nodes, `[[`, "value"),
                           sapply(top_nodes, `[[`, "role"))
    role_thresholds <- lapply(role_segments, function(v) {
      if (length(v) < 3) return(c(Inf, Inf))
      quantile(v, probs = c(0.25, 0.75))
    })

    build_nodes_df <- function(nodes) {
      do.call(rbind, lapply(seq_along(nodes), function(i) {
        n <- nodes[[i]]
        role <- n$role
        segs <- n$value
        bg <- n$color$background
        bd <- n$color$border
        hbg <- n$color$highlight$background
        hbd <- n$color$highlight$border
        # Vary shade: top 25% = original, middle 50% = lightened, bottom 25% = lightest
        th <- role_thresholds[[role]]
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
        data.frame(
          id = n$id,
          label = if (i == 1) n$label else "",
          origLabel = n$label,
          startLabel = if (i == 1) n$label else "",
          group = n$group,
          value = n$value, size = n$size * 0.7,
          baseSize = n$size * 0.7,
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
          stringsAsFactors = FALSE
        )
      }))
    }

    visNetwork(nodes = build_nodes_df(top_nodes),
               edges = build_edges_df(top_edges)) |>
      visNodes(font = list(size = 14, color = "#FFFFFF", face = "Arial",
               strokeWidth = 3, strokeColor = "#0f0f1a")) |>
      visEdges(smooth = FALSE,
               color = list(color = "#3498db", opacity = 1)) |>
      visInteraction(dragNodes = FALSE, dragView = TRUE, zoomView = TRUE) |>
      visPhysics(solver = "barnesHut", stabilization = list(enabled = TRUE, iterations = 500),
                 barnesHut = list(gravitationalConstant = -2000, springLength = 200,
                                  springConstant = 0.001, damping = 0.09)) |>
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
        if (params.nodes.length === 0) {
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
        }
      }")
  })

  output$overview_entities <- renderUI({
    top <- net$top_entities
    tags <- lapply(top, function(e) {
      tags$span(class = "entity-tag",
                paste0(e$value, " (", e$count, ")"))
    })
    do.call(tagList, tags)
  })

  observeEvent(input$legend_btn, {
    showModal(modalDialog(
      title = "Node Legend",
      tags$div(
        style = "display:flex; flex-direction:column; gap:10px;",
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:18px; height:18px;
            background:#FFD700; border:2px solid #B8860B; border-radius:2px;"),
          tags$span("Commissioner")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:18px; height:18px;
            background:#87CEEB; border:2px solid #4682B4; border-radius:2px;"),
          tags$span("Evidence Leader")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:18px; height:18px;
            background:#90EE90; border:2px solid #228B22; border-radius:50%;"),
          tags$span("Witness")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:18px; height:18px;
            background:#FF6347; border:2px solid #8B0000; border-radius:2px;"),
          tags$span("Protected Witness")),
        tags$div(style = "display:flex; align-items:center; gap:10px;",
          tags$span(style = "display:inline-block; width:18px; height:18px;
            background:#D3D3D3; border:2px solid #808080; border-radius:2px;"),
          tags$span("Other")),
        tags$hr(),
        tags$p(class = "text-muted", style = "font-size:0.8rem;",
          "Darker shade = more prominent. Lighter shade = less segments.")
      ),
      easyClose = TRUE, size = "s",
      footer = modalButton("Close")
    ))
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
    reactable(ctx[, c("hearing_date", "speaker", "context_text")],
      columns = list(
        hearing_date = colDef(name = "Date", width = 100),
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
    reactable(df[, c("hearing_date", "speaker", "speaker_role", "ctx")],
      columns = list(
        hearing_date = colDef(name = "Date", width = 100),
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
