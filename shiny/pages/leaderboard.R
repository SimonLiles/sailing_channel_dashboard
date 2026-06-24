# ====================================================================
#  Leaderboard — Report Builder
#  Build a custom leaderboard table by selecting the window, cohort,
#  rank-by metric, and which metric columns to display.
#
#  Data: leaderboard_rankings (global, long format)
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
      checkboxGroupInput("leaderboard_display_metrics",
        "Display metrics:", choices = NULL, inline = TRUE)
    )
  ),

  uiOutput("leaderboard_reactable")
)

# Server ----
leaderboard_server <- function(input, output, session) {

  # ---- Initialise inputs from data ----

  # Populate cohort choices once data is loaded
  observe({
    cohorts <- unique(leaderboard_rankings$cohort_type)
    updateSelectInput(session, "leaderboard_cohort",
      choices = cohorts, selected = "global")
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
    updateCheckboxGroupInput(session, "leaderboard_display_metrics",
      label = "Display metrics:",
      choices = choices, selected = default_display, inline = TRUE)
  })

  # ---- Cohort bucket UI ----

  output$leaderboard_bucket_ui <- renderUI({
    req(input$leaderboard_cohort)
    if (input$leaderboard_cohort == "global") {
      return(p(style = "padding-top: 25px; color: #999;",
               "Global ranking (all channels)"))
    }

    buckets <- leaderboard_rankings %>%
      filter(cohort_type == input$leaderboard_cohort) %>%
      distinct(cohort_value) %>%
      pull(cohort_value) %>%
      sort()

    selectInput("leaderboard_bucket", "Bucket:",
      choices = buckets, selected = buckets[1])
  })

  # ---- Data transformations ----

  # Filter long-format data to the selected window, cohort, and metrics
  leaderboard_filtered <- reactive({
    req(input$leaderboard_cohort, input$leaderboard_rank_by,
        input$leaderboard_display_metrics, input$leaderboard_window)

    selected_metrics <- unique(c(input$leaderboard_rank_by,
                                 input$leaderboard_display_metrics))

    wv <- if (input$leaderboard_window == "lifetime") {
      NA_integer_
    } else {
      as.integer(input$leaderboard_window)
    }

    data <- leaderboard_rankings %>%
      filter(cohort_type == input$leaderboard_cohort)

    if (input$leaderboard_cohort == "global") {
      data <- data %>% filter(cohort_value == "global")
    } else {
      req(input$leaderboard_bucket)
      data <- data %>% filter(cohort_value == input$leaderboard_bucket)
    }

    data <- data %>% filter(metric_name %in% selected_metrics)

    if (is.na(wv)) {
      data <- data %>% filter(is.na(window_days))
    } else {
      data <- data %>% filter(window_days == wv | is.na(window_days))
    }

    # Deduplicate: when a metric appears with both NULL and non-NULL
    # window_days (e.g. lifetime_views_per_vid), prefer the non-NULL row
    data %>%
      group_by(channel_id, metric_name) %>%
      slice_max(order_by = if_else(is.na(window_days), 0, 1), n = 1) %>%
      ungroup()
  })

  # Pivot to wide format and join channel info
  leaderboard_wide <- reactive({
    df <- leaderboard_filtered()
    req(nrow(df) > 0)

    wide <- df %>%
      select(channel_id, metric_name, metric_value, ranking, percentile) %>%
      pivot_wider(
        id_cols = channel_id,
        names_from = metric_name,
        values_from = c(metric_value, ranking, percentile),
        values_fn = \(x) x[[1]],          # safety: take first if duplicate
        names_glue = "{metric_name}_{.value}"
      ) %>%
      inner_join(channel_info, by = "channel_id")

    rank_col <- paste0(input$leaderboard_rank_by, "_ranking")
    if (rank_col %in% names(wide)) {
      wide <- wide %>% arrange(.data[[rank_col]])
    }
    wide
  })

  # ---- Reactable ----

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
      ),
      subscriber_count = colDef(
        name = "Subscribers", align = "right",
        cell = function(value) {
          if (is.na(value) || value < 1000) {
            formatC(value, format = "d", big.mark = ",")
          } else {
            paste0("~", format_youtube_style(value))
          }
        }
      ),
      view_count  = colDef(name = "Total Views", format = colFormat(separators = TRUE)),
      video_count = colDef(name = "Videos",       format = colFormat(separators = TRUE))
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

    rank_def <- setNames(list(colDef(name = "Rank", maxWidth = 80)), rank_col)

    c(rank_def, chan_defs, metric_defs)
  }

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
        "profile_pic", "channel_title", "channel_handle",
        "subscriber_count", "view_count", "video_count",
        paste0(display_metrics, "_metric_value")
      )
      keep_cols <- intersect(keep_cols, names(data))

      reactable(
        data[keep_cols],
        columns = col_defs,
        highlight = TRUE,
        striped = TRUE,
        searchable = TRUE,
        showPageSizeOptions = TRUE,
        pageSizeOptions = c(25, 50, 100)
      )
    })

    tagList(
      reactableOutput("leaderboard_table"),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "† Subscriber Count and New Subscribers are subject to YouTube's API
        resolution limits. Values are shown as reported and marked with ~ to
        indicate potential rounding. Channels with fewer than 1,000 subscribers
        are reported exactly. All other columns reflect precise values."
      ),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "†† Negative trailing averages indicate significant recent content removal,
        which affects rolling calculations. This may reflect a channel
        restructuring or content strategy change."
      )
    )
  })
}
