# UI ----
niche_pulse_ui <- nav_panel(
  "Niche Pulse",

  # Summary Stats
  layout_columns(
    fill = FALSE,
    value_box(
      title = "New Views (Last 24h)",
      value = textOutput("new_views_24h"),
      p(textOutput("avg_daily_views")),
      fill = FALSE,
    ),
    value_box(
      title = "Daily Average New Views (Last 7 Days)",
      value = textOutput("avg_new_views_7d"),
      fill = FALSE,
    ),
    value_box(
      title = "New Views Growth (Last 24h)",
      value = textOutput("view_growth_pct"),
      fill = FALSE,
    ),
    value_box(
      title = "New Subscribers (Last 24h)",
      value = textOutput("new_subs_24h"),
      p(textOutput("avg_daily_subs")),
      fill = FALSE,
    ),
    value_box(
      title = "Active Channels",
      value = textOutput("active_channels"),
      fill = FALSE,
    ),
  ),

  # Reactive Plot
  card(
    full_screen = TRUE,
    card_header("Niche Trends"),
    layout_sidebar(
      fillable = TRUE,
      sidebar = sidebar(
        title = "Plot Controls",
        position = "left",
        width = "20%",
        radioButtons(
          inputId = "macro_plot_column_selection",
          label = "Column Selection",
          choices = c(
            "Daily Views",
            "7 Day Average Views",
            "Daily Views Growth %",
            "Daily Sub Growth",
            "Active Channels"
          )
        ),
        dateRangeInput(
          inputId = "macro_plot_date_range",
          label = "Date Range",
          start = today - 365,
          end = today + 1,
          max = today + 1,
        ),
      ),
      plotlyOutput("macro_trend_plot"),
    ),
  ),
)

# Server ----
niche_pulse_server <- function(input, output, session) {

  output$new_views_24h <- renderText(
    formatC(global_summary$latest_views[1], format = "d", big.mark = ",")
  )

  output$avg_new_views_7d <- renderText(
    formatC(global_summary$views_moving_avg_7d[1], format = "d", big.mark = ",")
  )

  output$view_growth_pct <- renderText(
    format_dashboard_value(global_summary$view_growth_pct[1], is_pct = TRUE)
  )

  output$new_subs_24h <- renderText(
    formatC(global_summary$latest_subs[1], format = "d", big.mark = ",")
  )

  output$active_channels <- renderText(
    formatC(global_summary$active_channels[1], format = "d", big.mark = ",")
  )

  output$avg_daily_views <- renderText(
    paste(
      "Average New Views (Last 24h):",
      format_dashboard_value(global_summary$avg_daily_views[1])
    )
  )

  output$avg_daily_subs <- renderText(
    paste(
      "Average New Subscribers (Last 24h):",
      format_dashboard_value(global_summary$avg_daily_subs[1])
    )
  )

  output$macro_trend_plot <- renderPlotly({
    global_summary_filtered <- global_summary %>%
      filter(
        date >= input$macro_plot_date_range[1] &
          date <= input$macro_plot_date_range[2]
      )

    switch(input$macro_plot_column_selection,
      "Daily Views"          = { global_summary_filtered$data <- global_summary_filtered$latest_views },
      "7 Day Average Views"  = { global_summary_filtered$data <- global_summary_filtered$views_moving_avg_7d },
      "Daily Views Growth %" = { global_summary_filtered$data <- global_summary_filtered$view_growth_pct },
      "Daily Sub Growth"     = { global_summary_filtered$data <- global_summary_filtered$latest_subs },
      "Active Channels"      = { global_summary_filtered$data <- global_summary_filtered$active_channels },
    )

    ggplotly(
      ggplot(global_summary_filtered, aes(date, data)) +
        geom_line() +
        geom_point() +
        labs(
          x = "Date",
          y = input$macro_plot_column_selection
        ) +
        theme_minimal()
    )
  })
}
