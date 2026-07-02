# ====================================================================
#  Growth Benchmarks
#  Compare a selected channel's performance against other channels in
#  the selected cohort (e.g., global, subscriber count tier).
#
#  Data: leaderboard_rankings (long format with cohort_type / cohort_value)
#        channel_info         (one row per channel)
# ====================================================================

# UI ----
growth_benchmarks_ui <- nav_panel(
  "Growth Benchmarks",

  # Search bar
  fluidRow(
    column(12, align = "center",
      selectizeInput(
        "selected_channel_benchmarks",
        "Search for a Channel:",
        choices = NULL,
        options = list(
          placeholder = "Type a channel name...",
          allowClear = TRUE,
          minLength = 3,
          maxOptions = 10
        ),
      ),
    ),
  ),

  # Cohort selector (hidden until a channel is selected)
  uiOutput("cohort_selector_ui"),

  # Data area (hidden until a channel is selected)
  uiOutput("growth_metrics_ui"),
)

# Server ----
growth_benchmarks_server <- function(input, output, session) {

  updateSelectizeInput(
    session,
    "selected_channel_benchmarks",
    selected = character(0),
    choices = setNames(channel_info$channel_id, channel_info$channel_title),
    server = TRUE
  )

  # ---- Available cohort types ----
  cohort_types <- reactive({
    types <- get_leaderboard_cohorts()
    req(nrow(types) > 0)
    types <- unique(types$cohort_type)
    nice_names <- str_to_title(gsub("_", " ", types))
    set_names(types, nice_names)
  })

  # ---- Selected channel's cohort value for the chosen type ----
  selected_channel_cohort_value <- reactive({
    req(input$selected_channel_benchmarks)
    cohort <- input$benchmark_cohort_type %||% "global"
    result <- get_channel_cohort_value(input$selected_channel_benchmarks, cohort)
    req(nrow(result) > 0)
    result$cohort_value[1]
  })

  # ---- Format cohort label for display ----
  format_cohort_display <- reactive({
    req(selected_channel_cohort_value())
    ct <- input$benchmark_cohort_type %||% "global"
    cv <- selected_channel_cohort_value()
    if (ct == "global") return("All channels")
    if (ct == "subscriber_count") return(paste0(cv, " subscribers"))
    cv
  })

  # ---- Wide datasets for all channels in the selected cohort (30-day) ----

  benchmark_cohort_30d <- reactive({
    req(selected_channel_cohort_value())
    cohort <- input$benchmark_cohort_type %||% "global"
    cv <- selected_channel_cohort_value()
    get_benchmark_cohort(cohort, cv, 30L, exclude_metric = "lifetime_views_per_vid") %>%
      pivot_wider(
        id_cols = channel_id,
        names_from = metric_name,
        values_from = c(metric_value, ranking, percentile),
        names_glue = "{metric_name}_{.value}",
        values_fn = first
      ) %>%
      inner_join(channel_info, by = "channel_id")
  })

  benchmark_cohort_lifetime <- reactive({
    req(selected_channel_cohort_value())
    cohort <- input$benchmark_cohort_type %||% "global"
    cv <- selected_channel_cohort_value()
    get_benchmark_cohort(cohort, cv, NA_integer_) %>%
      pivot_wider(
        id_cols = channel_id,
        names_from = metric_name,
        values_from = c(metric_value, ranking, percentile),
        names_glue = "{metric_name}_{.value}",
        values_fn = first
      ) %>%
      inner_join(channel_info, by = "channel_id")
  })

  # ---- Selected channel data ----

  channel_growth_metrics <- reactive({
    req(input$selected_channel_benchmarks)
    benchmark_cohort_30d() %>%
      filter(channel_id == input$selected_channel_benchmarks)
  })

  channel_lifetime_metrics <- reactive({
    req(input$selected_channel_benchmarks)
    benchmark_cohort_lifetime() %>%
      filter(channel_id == input$selected_channel_benchmarks)
  })

  # ---- Cohort selector (only depends on channel selection, not cohort value) ----
  output$cohort_selector_ui <- renderUI({
    req(input$selected_channel_benchmarks)
    fluidRow(
      column(6,
        selectInput("benchmark_cohort_type", "Cohort:",
          choices = cohort_types(),
          selected = "global"
        ),
        h5(textOutput("cohort_label"))
      )
    )
  })

  output$cohort_label <- renderText({
    req(format_cohort_display())
    paste0("Channel is in: ", format_cohort_display())
  })

  # ---- Output UI ----

  output$growth_metrics_ui <- renderUI({
    req(input$selected_channel_benchmarks)

    fluidPage(
      fluidRow(
        h1(channel_growth_metrics()$channel_title)
      ),

      # Top metrics in value boxes ----
      layout_columns(
        fill = FALSE,
        value_box(
          title = "Views past 30 days",
          value = formatC(channel_growth_metrics()$total_views_window_metric_value, format = "d", big.mark = ","),
          h5(paste0(channel_growth_metrics()$total_views_window_percentile, "th percentile")),
          fill = FALSE
        ),
        value_box(
          title = "7 Day Average Views",
          value = format_dashboard_value(channel_lifetime_metrics()$views_moving_avg_7d_metric_value),
          h5(paste0(channel_lifetime_metrics()$views_moving_avg_7d_percentile, "th percentile")),
          fill = FALSE
        ),
        value_box(
          title = "New Subscribers past 30 days",
          value = formatC(channel_growth_metrics()$total_subs_window_metric_value, format = "d", big.mark = ","),
          h5(paste0(channel_growth_metrics()$total_subs_window_percentile, "th percentile")),
          fill = FALSE
        ),
        value_box(
          title = "Catalog Yield",
          value = format_dashboard_value(channel_growth_metrics()$views_per_vid_window_metric_value),
          h5(paste0(channel_growth_metrics()$views_per_vid_window_percentile, "th percentile")),
          p("Views per Video past 30 days"),
          fill = FALSE
        ),
        value_box(
          title = "Audience Activation",
          value = format_dashboard_value(channel_growth_metrics()$views_per_sub_window_metric_value),
          h5(paste0(channel_growth_metrics()$views_per_sub_window_percentile, "th percentile")),
          p("Views per Subscriber past 30 days"),
          fill = FALSE
        ),
      ),

      # Algorithmic performance charts ----
      card(
        card_header("Algorithmic Performance"),
        fluidRow(
          column(
            width = 6,
            card(
              plotlyOutput("algorithm_performance_chart"),
              full_screen = TRUE,
              fill = TRUE
            )
          ),
          column(
            width = 6,
            card(
              plotlyOutput("algorithm_performance_30d_chart"),
              full_screen = TRUE,
              fill = TRUE
            )
          )
        ),
        p("The above visualizations are plotting the subscriber count against
          the average number of views per video. Both axes are then converted to
          log 10 scales. This is a data visualization trick to spread the points
          close to the origin further apart, and group together points that are
          further from the origin. Without the transformation on the axes, almost
          all of the points would crowd the lower left corner, and the biggest
          channel (in this case: Sailing La Vagabonde) would be plotted in the
          upper right hand corner. With the squeezed data, in the lifetime data,
          a pattern becomes obvious, this is YouTube's algorithmic floor. Using
          a model, the performance of a channel can be predicted given a subscriber
          count. This prediction model is plotted over the data as the blue line."),
        fill = TRUE
      ),

      # Audience activation chart ----
      card(
        card_header("Audience Activation"),
        card(
          plotlyOutput("audience_activation_30d_chart"),
          full_screen = TRUE,
          fill = TRUE
        ),
        p("Plotted above is the audience activation against the subscriber count
          of active channels. Both axes have log 10 scales to group the data into
          a more easily read format. In general, healthy channels have an audience
          activation of 0.5 to 1 which indicates a healthy base of returning viewers.
          Values greater than 1 can also indicate growth if there is also a
          corresponding and current growth in subscribers.")
      )
    )
  })

  # ---- Growth metric plots ----

  output$algorithm_performance_chart <- renderPlotly(
    ggplotly(
      tooltip = "text",
      ggplot(benchmark_cohort_lifetime(), aes(x = subscriber_count, y = lifetime_views_per_vid_metric_value)) +
        geom_point(alpha = 1, color = "black", aes(text = channel_handle)) +
        geom_smooth(method = "lm") +
        annotate(
          geom = "point",
          x = channel_lifetime_metrics()$subscriber_count,
          y = channel_lifetime_metrics()$lifetime_views_per_vid_metric_value,
          text = channel_lifetime_metrics()$channel_handle,
          color = "red", size = 3, shape = "star"
        ) +
        scale_x_log10(labels = label_number()) +
        scale_y_log10(labels = label_number()) +
        ggtitle("Channel Performance, Lifetime Views per Video x Subscriber Count, log 10 scales") +
        labs(x = "Subscriber Count", y = "Views per Video (Lifetime)") +
        theme_minimal()
    )
  )

  output$algorithm_performance_30d_chart <- renderPlotly(
    ggplotly(
      tooltip = "text",
      ggplot(benchmark_cohort_30d(), aes(x = subscriber_count, y = views_per_vid_window_metric_value)) +
        geom_point(alpha = 1, color = "black", aes(text = channel_handle)) +
        geom_smooth(method = "lm") +
        annotate(
          geom = "point",
          x = channel_growth_metrics()$subscriber_count,
          y = channel_growth_metrics()$views_per_vid_window_metric_value,
          text = channel_growth_metrics()$channel_handle,
          color = "red", size = 3, shape = "star"
        ) +
        scale_x_log10(labels = label_number()) +
        scale_y_log10(labels = label_number()) +
        ggtitle("Channel Performance, 30 Day Views per Video x Subscriber Count, log 10 scales") +
        labs(x = "Subscriber Count", y = "Views per Video (30 Days)") +
        theme_minimal()
    )
  )

  output$audience_activation_30d_chart <- renderPlotly(
    ggplotly(
      tooltip = "text",
      ggplot(benchmark_cohort_30d(), aes(x = subscriber_count, y = views_per_sub_window_metric_value)) +
        geom_point(alpha = 1, color = "black", aes(text = channel_handle)) +
        geom_smooth(method = "lm") +
        annotate(
          geom = "point",
          x = channel_growth_metrics()$subscriber_count,
          y = channel_growth_metrics()$views_per_sub_window_metric_value,
          text = channel_growth_metrics()$channel_handle,
          color = "red", size = 3, shape = "star"
        ) +
        scale_x_log10(labels = label_number()) +
        scale_y_log10(labels = label_number()) +
        ggtitle("Audience Activation, 30 Day Views per Subscriber x Subscriber Count, log 10 scales") +
        labs(x = "Subscriber Count", y = "Views per Subscriber (30 Days)") +
        theme_minimal()
    )
  )
}
