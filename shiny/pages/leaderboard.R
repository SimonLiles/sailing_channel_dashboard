# ====================================================================
#  Leaderboard — Report Builder (Keyset-Paginated)
#  Build a custom leaderboard table by selecting the window, cohort,
#  rank-by metric, and which metric columns to display.
#
#  Data: mart_channel_rankings + mart_channel_metrics_values (BigQuery)
#        channel_info         (global, one row per channel)
# ====================================================================

# Metric metadata
metric_meta <- tibble::tribble(
  ~metric_name,             ~display_label,       ~window_group, ~default_show, ~format_type,
  "total_views_window",     "Views",              "windowed",    TRUE,          "integer",
  "total_subs_window",      "New Subscribers",    "windowed",    TRUE,          "integer",
  "new_videos_window",      "New Videos",         "windowed",    FALSE,         "integer",
  "sub_conversion_rate",    "Sub Conv. Rate",     "windowed",    FALSE,         "decimal",
  "subs_pct_growth",        "Sub Growth %",       "windowed",    TRUE,          "decimal",
  "views_per_vid_window",   "Views/Video",        "windowed",    TRUE,          "decimal",
  "views_per_sub_window",   "Views/Sub",          "windowed",    FALSE,         "decimal",
  "views_moving_avg_7d",    "7D Avg Views",       "snapshot",    TRUE,          "decimal",
  "daily_new_subs",         "Daily New Subs",     "snapshot",    FALSE,         "integer",
  "subscriber_count",       "Subscribers",        "lifetime",    TRUE,          "integer",
  "view_count",             "Total Views",        "lifetime",    TRUE,          "integer",
  "video_count",            "Videos",             "lifetime",    FALSE,         "integer",
  "lifetime_views_per_vid", "Views/Video (All)",  "lifetime",    FALSE,         "decimal",
  "lifetime_views_per_sub", "Views/Sub (All)",    "lifetime",    FALSE,         "decimal"
)

# Cohort metadata
cohort_meta <- tibble::tribble(
  ~cohort_type,      ~display_label,
  "global",           "Global",
  "subscriber_count", "Subscriber Count"
)

cohort_bucket_order <- list(
  subscriber_count = c("<1K", "1k- 10K", "10K - 100k",
                       "100K - 500k", "500K - 1M", "1M - 10M", "10M+")
)

# UI ----
leaderboard_ui <- nav_panel(
  "The Leaderboard",

  fluidRow(
    column(3,
      selectInput("leaderboard_window", "Window:",
        choices = c("30 days" = "30", "90 days" = "90",
                    "180 days" = "180", "365 days" = "365",
                    "Lifetime" = "lifetime"),
        selected = "30")
    ),
    column(3,
      selectInput("leaderboard_cohort", "Cohort:", choices = NULL)
    ),
    column(3,
      uiOutput("leaderboard_bucket_ui")
    )
  ),

  fluidRow(
    column(4,
      selectInput("leaderboard_rank_by", "Rank by:", choices = NULL)
    ),
    column(8,
      selectInput("leaderboard_display_metrics", "Display metrics:",
        choices = NULL, multiple = TRUE)
    )
  ),

  fluidRow(
    column(6,
      textInput("leaderboard_search", "Search channel:",
        placeholder = "Type a channel name or handle...")
    ),
    column(6, align = "right",
      selectInput("leaderboard_page_size", "Rows per page:",
        choices = c(25, 50, 100), selected = 25, width = "150px")
    )
  ),

  withSpinner(
    uiOutput("leaderboard_reactable"),
    type = 8,
    color = "#002B5B",
    caption = "Loading leaderboard data..."
  )
)

# Server ----
leaderboard_server <- function(input, output, session) {

  # ---- Initialise inputs from data ----

  # Populate cohort choices from BigQuery
  observe({
    cohorts <- get_leaderboard_cohorts()
    req(nrow(cohorts) > 0)
    types <- unique(cohorts$cohort_type)
    idx <- match(types, cohort_meta$cohort_type)
    labels <- ifelse(is.na(idx), types, cohort_meta$display_label[idx])
    choices <- setNames(types, labels)
    updateSelectInput(session, "leaderboard_cohort",
      choices = choices, selected = "global")
  })

  # Populate rank_by and display_metrics when window changes
  observeEvent(input$leaderboard_window, {
    m <- if (input$leaderboard_window == "lifetime") {
      metric_meta %>% filter(window_group == "lifetime")
    } else {
      metric_meta
    }

    choices <- setNames(m$metric_name, m$display_label)
    default_rank <- m$metric_name[1]

    updateSelectInput(session, "leaderboard_rank_by",
      choices = choices, selected = default_rank)

    default_display <- m %>% filter(default_show) %>% pull(metric_name)
    updateSelectInput(session, "leaderboard_display_metrics",
      label = "Display metrics:",
      choices = choices, selected = default_display)
  })

  # ---- Cohort bucket UI ----

  output$leaderboard_bucket_ui <- renderUI({
    req(input$leaderboard_cohort)
    if (input$leaderboard_cohort == "global") {
      return(p(style = "padding-top: 25px; color: #999;",
               "Global ranking (all channels)"))
    }

    result <- get_leaderboard_buckets(input$leaderboard_cohort)
    req(nrow(result) > 0)
    buckets <- result$cohort_value

    if (input$leaderboard_cohort %in% names(cohort_bucket_order)) {
      order <- cohort_bucket_order[[input$leaderboard_cohort]]
      buckets <- order[order %in% buckets]
    } else {
      buckets <- sort(buckets)
    }

    selectInput("leaderboard_bucket", "Bucket:",
      choices = buckets, selected = buckets[1])
  })

  # ---- Derived filter values ----

  # Window days (NA for lifetime)
  window_days <- reactive({
    if (input$leaderboard_window == "lifetime") NA_integer_ else as.integer(input$leaderboard_window)
  })

  # Cohort value string
  cohort_value <- reactive({
    if (input$leaderboard_cohort == "global") {
      "global"
    } else {
      req(input$leaderboard_bucket)
      input$leaderboard_bucket
    }
  })

  # All selected metrics (rank_by + display)
  selected_metrics <- reactive({
    unique(c(input$leaderboard_rank_by, input$leaderboard_display_metrics))
  })

  # Debounced search
  search_debounced <- reactive(input$leaderboard_search) %>% debounce(500)

  # ---- Pagination state ----

  r <- reactiveValues(
    page          = 1L,
    total         = 0L,
    prev_page     = 0L,
    first_cursor  = list(ranking = NULL, channel_id = NULL),
    last_cursor   = list(ranking = NULL, channel_id = NULL)
  )

  # ---- Filter changes → reset pagination and recount ----

  observeEvent(list(
    input$leaderboard_window,
    input$leaderboard_cohort,
    input$leaderboard_bucket,
    input$leaderboard_rank_by,
    input$leaderboard_display_metrics,
    search_debounced(),
    input$leaderboard_page_size
  ), {
    req(input$leaderboard_cohort, input$leaderboard_rank_by)

    r$page <- 1L
    r$prev_page <- 0L
    r$first_cursor <- list(ranking = NULL, channel_id = NULL)
    r$last_cursor  <- list(ranking = NULL, channel_id = NULL)

    isolate({
      cv <- cohort_value()
      wv <- window_days()
      result <- get_leaderboard_count(
        cohort_type    = input$leaderboard_cohort,
        cohort_value   = cv,
        rank_by_metric = input$leaderboard_rank_by,
        window_days    = wv,
        search_query   = search_debounced()
      )
      r$total <- result$total_channels[1] %||% 0L
    })
  }, ignoreNULL = FALSE)

  # ---- Navigation ----

  observeEvent(input$leaderboard_next, {
    r$prev_page <- r$page
    r$page <- r$page + 1L
  })

  observeEvent(input$leaderboard_prev, {
    r$prev_page <- r$page
    r$page <- r$page - 1L
  })

  # ---- Main data fetch ----

  leaderboard_page <- eventReactive(list(
    r$page,
    input$leaderboard_window,
    input$leaderboard_cohort,
    input$leaderboard_bucket,
    input$leaderboard_rank_by,
    input$leaderboard_display_metrics,
    search_debounced(),
    input$leaderboard_page_size
  ), {
    req(input$leaderboard_cohort, input$leaderboard_rank_by,
        input$leaderboard_display_metrics)

    isolate({
      cv  <- cohort_value()
      wv  <- window_days()
      sm  <- selected_metrics()
      psz <- as.integer(input$leaderboard_page_size %||% 25L)

      # Determine cursor and direction from pagination state
      if (r$page == 1L) {
        cursor_rank <- NULL
        cursor_cid  <- NULL
        dir <- "next"
        r$prev_page <- 0L
      } else if (r$page > r$prev_page) {
        cursor_rank <- r$last_cursor$ranking
        cursor_cid  <- r$last_cursor$channel_id
        dir <- "next"
      } else {
        cursor_rank <- r$first_cursor$ranking
        cursor_cid  <- r$first_cursor$channel_id
        dir <- "prev"
      }

      data <- get_leaderboard_page(
        cohort_type       = input$leaderboard_cohort,
        cohort_value      = cv,
        rank_by_metric    = input$leaderboard_rank_by,
        window_days       = wv,
        page_size         = psz,
        selected_metrics  = sm,
        cursor_ranking    = cursor_rank,
        cursor_channel_id = cursor_cid,
        direction         = dir,
        search_query      = search_debounced()
      )

      data
    })
  })

  # ---- Update cursors after data arrives ----

  observeEvent(leaderboard_page(), {
    req(nrow(leaderboard_page()) > 0)
    isolate({
      rank_rows <- leaderboard_page() %>%
        filter(metric_name == input$leaderboard_rank_by)

      if (nrow(rank_rows) > 0) {
        r$first_cursor <- list(
          ranking    = rank_rows$ranking[1],
          channel_id = rank_rows$channel_id[1]
        )
        r$last_cursor <- list(
          ranking    = rank_rows$ranking[nrow(rank_rows)],
          channel_id = rank_rows$channel_id[nrow(rank_rows)]
        )
      }
    })
  })

  # ---- Deduplicate and pivot ----

  leaderboard_wide <- reactive({
    df <- leaderboard_page()
    req(nrow(df) > 0)

    # Deduplicate: when a metric appears with both NULL and non-NULL
    # window_days (e.g. lifetime_views_per_vid), prefer the non-NULL row
    df <- df %>%
      group_by(channel_id, metric_name) %>%
      slice_max(order_by = if_else(is.na(window_days), 0, 1), n = 1) %>%
      ungroup()

    wide <- df %>%
      select(channel_id, metric_name, metric_value,
             ranking, percentile, prev_ranking, rank_change) %>%
      pivot_wider(
        id_cols     = channel_id,
        names_from  = metric_name,
        values_from = c(metric_value, ranking, percentile,
                        prev_ranking, rank_change),
        values_fn   = \(x) x[[1]],
        names_glue  = "{metric_name}_{.value}"
      ) %>%
      inner_join(channel_info, by = "channel_id")

    rank_col <- paste0(input$leaderboard_rank_by, "_ranking")
    if (rank_col %in% names(wide)) {
      wide <- wide %>% arrange(.data[[rank_col]])
    }
    wide
  })

  # ---- Reactable column definitions ----

  build_col_defs <- function(rank_by, display_metrics, data) {
    rank_col <- paste0(rank_by, "_ranking")

    chan_defs <- list(
      profile_pic = colDef(
        name = "", maxWidth = 60,
        cell = function(value) {
          tags$img(src = value, height = "40px", width = "40px",
                   style = "border-radius: 50%; object-fit: cover;")
        }
      ),
      channel_title = colDef(name = "Creator", minWidth = 150),
      channel_handle = colDef(
        name = "Handle", minWidth = 120,
        style = list(whiteSpace = "nowrap"),
        cell = function(value) {
          tags$a(href = paste0("https://www.youtube.com/", value),
                 target = "_blank", value)
        }
      )
    )

    metric_defs <- list()
    for (m in display_metrics) {
      display_name <- metric_meta$display_label[metric_meta$metric_name == m]
      if (length(display_name) == 0) display_name <- m
      fmt_type <- metric_meta$format_type[metric_meta$metric_name == m]
      digits <- if (length(fmt_type) > 0 && fmt_type == "integer") 0 else 2
      value_col <- paste0(m, "_metric_value")
      metric_defs[[value_col]] <- colDef(
        name = display_name, align = "right",
        format = colFormat(separators = TRUE, digits = digits)
      )
    }

    # Override subscriber_count with YouTube-style formatting
    if ("subscriber_count" %in% display_metrics) {
      metric_defs[["subscriber_count_metric_value"]] <- colDef(
        name = "Subscribers", align = "right",
        cell = function(value) {
          if (is.na(value) || value < 1000) {
            formatC(value, format = "d", big.mark = ",")
          } else {
            paste0("~", format_youtube_style(value))
          }
        }
      )
    }

    rank_def <- setNames(list(colDef(name = "Rank", maxWidth = 80)), rank_col)

    rank_change_col <- paste0(rank_by, "_rank_change")
    rank_change_def <- setNames(
      list(colDef(
        name = "\u0394", maxWidth = 65, align = "right",
        cell = function(value) {
          if (is.na(value)) {
            tags$span(style = "color: #999;", "\u2014")
          } else if (value > 0) {
            tags$span(style = "color: #22c55e; font-weight: bold;",
                      paste0("\u25B2 +", value))
          } else if (value < 0) {
            tags$span(style = "color: #ef4444; font-weight: bold;",
                      paste0("\u25BC ", value))
          } else {
            tags$span(style = "color: #999;", "\u2014")
          }
        }
      )),
      rank_change_col
    )

    c(rank_def, rank_change_def, chan_defs, metric_defs)
  }

  # ---- Render reactable with pagination controls ----

  total_pages <- reactive({
    ps <- as.integer(input$leaderboard_page_size %||% 25L)
    ceiling(r$total / ps)
  })

  output$leaderboard_reactable <- renderUI({
    req(leaderboard_wide())

    data <- leaderboard_wide()
    display_metrics <- input$leaderboard_display_metrics[
      paste0(input$leaderboard_display_metrics, "_metric_value") %in% names(data)
    ]
    rank_by <- input$leaderboard_rank_by

    col_defs <- build_col_defs(rank_by, display_metrics, data)

    output$leaderboard_table <- renderReactable({
      keep_cols <- c(
        paste0(rank_by, "_ranking"),
        paste0(rank_by, "_rank_change"),
        "profile_pic", "channel_title", "channel_handle",
        paste0(display_metrics, "_metric_value")
      )
      keep_cols <- intersect(keep_cols, names(data))

      reactable(
        data[keep_cols],
        columns    = col_defs,
        highlight  = TRUE,
        striped    = TRUE,
        searchable = FALSE,
        pagination = FALSE
      )
    })

    # Pagination controls
    tp <- total_pages()
    has_prev <- r$page > 1L
    has_next <- r$page < tp

    tagList(
      reactableOutput("leaderboard_table"),
      br(),
      fluidRow(
        column(12, align = "center",
          div(style = "display: inline-flex; align-items: center; gap: 12px;",
            actionButton("leaderboard_prev", "\u25C0 Prev",
              disabled = !has_prev),
            span(style = "font-weight: 500;",
              "Page ", r$page, " of ", tp,
              " (", r$total, " channels)"
            ),
            actionButton("leaderboard_next", "Next \u25B6",
              disabled = !has_next)
          )
        )
      ),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "\u2020 Subscriber Count and New Subscribers are subject to YouTube's API
        resolution limits. Values are shown as reported and marked with ~ to
        indicate potential rounding. Channels with fewer than 1,000 subscribers
        are reported exactly. All other columns reflect precise values."
      ),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "\u2020\u2020 Negative trailing averages indicate significant recent content removal,
        which affects rolling calculations. This may reflect a channel
        restructuring or content strategy change."
      )
    )
  })
}
