# Plan: Add Dashboard Full Page with Accusation & Evidence Stats

## Summary

Add a new `nav_panel("Dashboard")` full page to the Shiny app that displays:
- Summary stat cards (hearings, witnesses, segments, documents, accusations, corroborated)
- Top accused entities table with corroboration status
- Evidence validity breakdown

All changes are additive -- nothing existing is modified or removed. Only `app.R` and `global.R` are touched.

---

## Change 1: `commission_research/app/global.R`

**Add after line 178 (end of file):**

```r
get_accusation_stats <- function(conn) {
  as.data.frame(dbGetQuery(conn,
    "SELECT entity_type, COUNT(*) AS total_mentions,
            COUNT(DISTINCT entity_value) AS unique_entities
     FROM entities
     WHERE entity_type IN ('organization', 'case_reference', 'exhibit')
     GROUP BY entity_type
     ORDER BY total_mentions DESC"
  ))
}

get_top_accused <- function(conn, limit = 25) {
  as.data.frame(dbGetQuery(conn,
    "SELECT e.entity_value, e.entity_type, COUNT(*) AS mentions,
            COUNT(DISTINCT e.speaker_id) AS witnesses
     FROM entities e
     WHERE e.entity_type IN ('organization', 'case_reference', 'exhibit')
     GROUP BY e.entity_value, e.entity_type
     ORDER BY mentions DESC
     LIMIT ?",
    params = list(limit)))
}
```

These are database query helpers useful for both the dashboard and any future features.

---

## Change 2: `commission_research/app/app.R` -- Insert Dashboard nav_panel in UI

**Insert the following code between lines 308 and 309** (between the closing `)` of the Evidence Compare `nav_panel` and the `nav_menu("Stats",` line):

```r

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
```

This adds the Dashboard as a new top-level nav panel between Evidence Compare and the Stats dropdown. The layout uses:
- **Row 1**: 6 stat summary cards with colored top borders (reuses existing `.stat-card` CSS class)
- **Row 2**: Full-width card with a reactable table of the top 25 accused entities, each flagged as corroborated or testimony-only
- **Row 3**: Two-column layout with corroboration percentage/summary on the left and a corroboration-by-type table on the right

---

## Change 3: `commission_research/app/app.R` -- Insert Dashboard server code

**Insert the following code after line 360** (after the empty line following the Overview Stats section closing `})`, before the `# ── Overview Mini Network` comment on line 361):

```r

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
```

This server code:
- Loads story map data (`load_story_map()` uses caching so it's efficient)
- Wires up all 6 stat card outputs from `network_data.json` and `story_map_data.json`
- Queries the `entities` table for accusation counts and top accused entities
- Cross-references each accused entity against the story map's `shared_entities` to determine corroboration
- Renders two reactable tables with the existing dark theme

---

## What is NOT changed

- Existing Stats dropdown in navbar -- completely untouched (lines 309-331)
- All 8 existing nav_panels -- zero modifications
- Database schema -- read-only queries only
- Pipeline scripts (`compute_network.py`, `build_story_map.py`, etc.)
- CSS styles -- reuses existing `.stat-card` class

## Verification

After applying these changes, run the Shiny app and verify:
1. "Dashboard" appears as a new nav tab between "Evidence Compare" and "Stats" dropdown
2. Stat cards show correct counts (hearings, witnesses, segments, documents, accusations, corroborated)
3. The "Top Accused Entities" table loads with entities, types, mention counts, witness counts, and corroboration status
4. The "Evidence Corroboration" section shows a percentage and breakdown table
5. All existing pages continue to work without any disruption
