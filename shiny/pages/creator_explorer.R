# UI ----
creator_explorer_ui <- nav_panel(
  "Creator Explorer",

  # Search bar
  fluidRow(
    column(12, align = "center",
      selectizeInput(
        "selected_channel",
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

  # Data area (hidden until a channel is selected)
  withSpinner(
    uiOutput("channel_dashboard_ui"),
    type = 8,
    color = "#002B5B",
    caption = "Loading channel data..."
  ),
)

# Server ----
creator_explorer_server <- function(input, output, session) {

  updateSelectizeInput(
    session,
    "selected_channel",
    selected = character(0),
    choices = setNames(channel_info$channel_id, channel_info$channel_title),
    server = TRUE
  )

  channel_profile <- reactive({
    req(input$selected_channel)
    message(paste("Querying channel profile for:", input$selected_channel))
    run_channel_query(
      here("sql", "04_apps", "get_channel_profile.sql"),
      params = list(id = input$selected_channel)
    )
  })

  channel_history <- reactive({
    req(input$selected_channel)
    message(paste("Querying channel history for:", input$selected_channel))
    run_channel_query(
      here("sql", "04_apps", "get_channel_history.sql"),
      params = list(id = input$selected_channel)
    )
  })

  output$channel_dashboard_ui <- renderUI({
    req(input$selected_channel)

    # Time series plots ----
    output$subscriber_count_ts_plot <- renderPlotly({
      plot_ly(channel_history()) %>%
        add_lines(
          x = ~date, y = ~subscriber_count,
          color = I("black"), span = I(1),
          fill = "tozeroy", alpha = 0.2
        ) %>%
        layout(
          xaxis = list(visible = F, showgrid = F, title = ""),
          yaxis = list(visible = F, showgrid = F, title = ""),
          hovermode = "x",
          margin = list(t = 0, r = 0, l = 0, b = 0),
          font = list(color = "black"),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent"
        ) %>%
        plotly::config(displayModeBar = F) %>%
        htmlwidgets::onRender(
          "function(el) {
            el.closest('.bslib-value-box')
              .addEventListener('bslib.card', function(ev) {
                Plotly.relayout(el, {'xaxis.visible': ev.detail.fullScreen});
              })
          }"
        )
    })

    output$daily_views_ts_plot <- renderPlotly({
      plot_ly(channel_history()) %>%
        add_lines(
          x = ~date, y = ~daily_new_views,
          color = I("black"), span = I(1),
          fill = "tozeroy", alpha = 0.2
        ) %>%
        layout(
          xaxis = list(visible = F, showgrid = F, title = ""),
          yaxis = list(visible = F, showgrid = F, title = ""),
          hovermode = "x",
          margin = list(t = 0, r = 0, l = 0, b = 0),
          font = list(color = "black"),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent"
        ) %>%
        plotly::config(displayModeBar = F) %>%
        htmlwidgets::onRender(
          "function(el) {
            el.closest('.bslib-value-box')
              .addEventListener('bslib.card', function(ev) {
                Plotly.relayout(el, {'xaxis.visible': ev.detail.fullScreen});
              })
          }"
        )
    })

    output$video_count_ts_plot <- renderPlotly({
      plot_ly(channel_history()) %>%
        add_lines(
          x = ~date, y = ~video_count,
          color = I("black"), span = I(1),
          fill = "tozeroy", alpha = 0.2
        ) %>%
        layout(
          xaxis = list(visible = F, showgrid = F, title = ""),
          yaxis = list(visible = F, showgrid = F, title = ""),
          hovermode = "x",
          margin = list(t = 0, r = 0, l = 0, b = 0),
          font = list(color = "black"),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent"
        ) %>%
        plotly::config(displayModeBar = F) %>%
        htmlwidgets::onRender(
          "function(el) {
            el.closest('.bslib-value-box')
              .addEventListener('bslib.card', function(ev) {
                Plotly.relayout(el, {'xaxis.visible': ev.detail.fullScreen});
              })
          }"
        )
    })

    output$views_7d_avg_ts_plot <- renderPlotly({
      plot_ly(channel_history()) %>%
        add_lines(
          x = ~date, y = ~views_moving_avg_7d,
          color = I("black"), span = I(1),
          fill = "tozeroy", alpha = 0.2
        ) %>%
        layout(
          xaxis = list(visible = F, showgrid = F, title = ""),
          yaxis = list(visible = F, showgrid = F, title = ""),
          hovermode = "x",
          margin = list(t = 0, r = 0, l = 0, b = 0),
          font = list(color = "black"),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent"
        ) %>%
        plotly::config(displayModeBar = F) %>%
        htmlwidgets::onRender(
          "function(el) {
            el.closest('.bslib-value-box')
              .addEventListener('bslib.card', function(ev) {
                Plotly.relayout(el, {'xaxis.visible': ev.detail.fullScreen});
              })
          }"
        )
    })

    if (is.na(channel_profile()$status)) {
      channel_status <- "Sailing"
    } else {
      channel_status <- channel_profile()$status
    }

    if (is.na(channel_profile()$type)) {
      channel_type <- "Sailing Vlog"
    } else {
      channel_type <- channel_profile()$type
    }

    tagList(
      fluidRow(
        # About the channel ----
        column(
          width = 6,
          fluidRow(
            column(
              width = 2,
              htmlOutput("profile_card"),
            ),
            column(
              width = 5,
              h2(channel_profile()$channel_title),
              p(channel_profile()$channel_handle),
              p(paste("Joined:", channel_profile()$join_date)),
              p(paste("Status:", channel_status)),
              p(paste("Type:", channel_type)),
            ),
            column(
              width = 3,
              actionButton(
                "channel_link",
                label = "Find on YouTube",
                icon = icon("external-link-alt"),
                onclick = paste0(
                  "window.open('https://www.youtube.com/",
                  channel_profile()$channel_handle,
                  "', '_blank');"
                ),
              )
            )
          ),
          br(),
          h3("About:"),
          p(channel_profile()$channel_description),
        ),

        # Primary metrics ----
        column(
          width = 3,
          value_box(
            title = "Subscriber Count",
            value = formatC(
              tail(channel_history()$subscriber_count, n = 1),
              big.mark = ",",
            ),
            showcase = plotlyOutput("subscriber_count_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
          value_box(
            title = "New Views (Last 24h)",
            value = formatC(
              tail(channel_history()$daily_new_views, n = 1),
              big.mark = ",",
            ),
            showcase = plotlyOutput("daily_views_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
        ),
        column(
          width = 3,
          value_box(
            title = "Video Count",
            value = formatC(
              tail(channel_history()$video_count, n = 1),
              big.mark = ",",
            ),
            showcase = plotlyOutput("video_count_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
          value_box(
            title = "7 Day Average Views",
            value = format(
              tail(channel_history()$views_moving_avg_7d, n = 1),
              big.mark = ",",
            ),
            showcase = plotlyOutput("views_7d_avg_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
        ),
      ),

      # 2nd row ----
      fluidRow(
        column(
          width = 6,
          card(
            card_header("Channel Tags"),
            htmlOutput("keyword_pills"),
          )
        ),
        column(
          width = 6,
        ),
      ),

      # Negative value footnote
      if (any(c(
        tail(channel_history()$subscriber_count, n = 1),
        tail(channel_history()$daily_new_views, n = 1),
        tail(channel_history()$video_count, n = 1),
        tail(channel_history()$views_moving_avg_7d, n = 1)
      ) < 0)) {
        tags$p(
          class = "text-muted fst-italic mt-3 px-3",
          icon("circle-info", lib = "font-awesome"),
          "Negative trailing averages indicate significant recent content removal,
           which affects rolling calculations. This may reflect a channel
           restructuring or content strategy change."
        )
      }
    )
  })

  output$profile_card <- renderUI({
    req(channel_profile())
    tags$img(
      src = channel_profile()$profile_pic,
      width = "100%",
      style = "border-radius: 10px;"
    )
  })

  output$keyword_pills <- renderUI({
    profile <- channel_profile()
    req(profile$channel_keywords)

    keywords <- str_extract_all(profile$channel_keywords, '"[^"]+"|[\\S]+')[[1]]
    keywords <- gsub('\"', "", keywords)
    keywords <- gsub(",", "", keywords)
    keywords <- trimws(keywords)
    keywords <- keywords[keywords != ""]

    tagList(
      tags$div(
        class = "pill-container",
        lapply(keywords, function(k) {
          tags$span(class = "keyword-pill", k)
        })
      ),
    )
  })
}
