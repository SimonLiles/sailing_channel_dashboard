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

    prof <- channel_profile()
    hist <- channel_history()

    # Coalesced profile fields (cold-start safe: a 0-row profile yields
    # NULL/empty, a 1-row unenriched profile yields NA).
    channel_title <- coalesce_profile_field(prof$channel_title)
    channel_handle <- coalesce_profile_field(prof$channel_handle)
    channel_description <- coalesce_profile_field(prof$channel_description)
    channel_join_date <- coalesce_profile_field(prof$join_date)
    channel_pic <- prof$profile_pic
    if (is.null(channel_pic) || length(channel_pic) == 0 ||
        isTRUE(is.na(channel_pic))) {
      channel_pic <- NULL
    }
    channel_status <- coalesce_profile_field(prof$status, fallback = "Sailing")
    channel_type <- coalesce_profile_field(prof$type, fallback = "Sailing Vlog")
    channel_link <- if (identical(channel_handle, "N/A")) {
      NULL
    } else {
      paste0("https://www.youtube.com/", channel_handle)
    }

    # Latest metric values (NA-safe tails: NULL/empty/NA -> NA_real_).
    last_subs <- safe_tail1(hist$subscriber_count)
    last_daily_views <- safe_tail1(hist$daily_new_views)
    last_videos <- safe_tail1(hist$video_count)
    last_avg7 <- safe_tail1(hist$views_moving_avg_7d)

    pending_notice_ui <- tags$div(
      class = "alert alert-info",
      role = "alert",
      icon("circle-info", lib = "font-awesome"),
      paste(
        "This channel was recently added — its metrics are still",
        "populating. Check back after the next ETL run."
      )
    )

    header_ui <- fluidRow(
      column(
        width = 2,
        htmlOutput("profile_card"),
      ),
      column(
        width = 5,
        h2(channel_title),
        p(channel_handle),
        p(paste("Joined:", channel_join_date)),
        p(paste("Status:", channel_status)),
        p(paste("Type:", channel_type)),
      ),
      column(
        width = 3,
        actionButton(
          "channel_link",
          label = "Find on YouTube",
          icon = icon("external-link-alt"),
          onclick = if (is.null(channel_link)) {
            NULL
          } else {
            paste0("window.open('", channel_link, "', '_blank');")
          },
        )
      )
    )

    # Cold-start: channel added, ETL enrichment pending — no history yet.
    # Render the profile header plus a notice instead of crashing.
    if (is.null(hist) || nrow(hist) == 0) {
      return(
        tagList(
          header_ui,
          br(),
          h3("About:"),
          p(channel_description),
          br(),
          pending_notice_ui,
        )
      )
    }

    # Time series plots ----
    output$subscriber_count_ts_plot <- renderPlotly({
      if (!has_series(channel_history()$subscriber_count)) {
        return(
          plot_ly() %>%
            layout(
              annotations = list(
                text = "Insufficient history",
                showarrow = FALSE,
                font = list(color = "black")
              ),
              xaxis = list(visible = F, showgrid = F),
              yaxis = list(visible = F, showgrid = F),
              paper_bgcolor = "transparent",
              plot_bgcolor = "transparent"
            ) %>%
            plotly::config(displayModeBar = F)
        )
      }
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
      if (!has_series(channel_history()$daily_new_views)) {
        return(
          plot_ly() %>%
            layout(
              annotations = list(
                text = "Insufficient history",
                showarrow = FALSE,
                font = list(color = "black")
              ),
              xaxis = list(visible = F, showgrid = F),
              yaxis = list(visible = F, showgrid = F),
              paper_bgcolor = "transparent",
              plot_bgcolor = "transparent"
            ) %>%
            plotly::config(displayModeBar = F)
        )
      }
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
      if (!has_series(channel_history()$video_count)) {
        return(
          plot_ly() %>%
            layout(
              annotations = list(
                text = "Insufficient history",
                showarrow = FALSE,
                font = list(color = "black")
              ),
              xaxis = list(visible = F, showgrid = F),
              yaxis = list(visible = F, showgrid = F),
              paper_bgcolor = "transparent",
              plot_bgcolor = "transparent"
            ) %>%
            plotly::config(displayModeBar = F)
        )
      }
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
      if (!has_series(channel_history()$views_moving_avg_7d)) {
        return(
          plot_ly() %>%
            layout(
              annotations = list(
                text = "Insufficient history",
                showarrow = FALSE,
                font = list(color = "black")
              ),
              xaxis = list(visible = F, showgrid = F),
              yaxis = list(visible = F, showgrid = F),
              paper_bgcolor = "transparent",
              plot_bgcolor = "transparent"
            ) %>%
            plotly::config(displayModeBar = F)
        )
      }
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

    tagList(
      # Cold-start notice: flow metrics pending ETL enrichment.
      if (flows_pending(hist)) {
        fluidRow(column(width = 12, pending_notice_ui))
      },
      fluidRow(
        # About the channel ----
        column(
          width = 6,
          header_ui,
          br(),
          h3("About:"),
          p(channel_description),
        ),

        # Primary metrics ----
        column(
          width = 3,
          value_box(
            title = "Subscriber Count",
            value = format_count_safe(last_subs),
            showcase = plotlyOutput("subscriber_count_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
          value_box(
            title = "New Views (Last 24h)",
            value = format_count_safe(last_daily_views),
            showcase = plotlyOutput("daily_views_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
        ),
        column(
          width = 3,
          value_box(
            title = "Video Count",
            value = format_count_safe(last_videos),
            showcase = plotlyOutput("video_count_ts_plot"),
            fill = FALSE,
            full_screen = TRUE,
          ),
          value_box(
            title = "7 Day Average Views",
            value = format_dashboard_value(last_avg7),
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

      # Negative value footnote (NA-safe: cold-start NA tails -> FALSE)
      if (show_negative_note(list(
        subscriber_count = hist$subscriber_count,
        daily_new_views = hist$daily_new_views,
        video_count = hist$video_count,
        views_moving_avg_7d = hist$views_moving_avg_7d
      ))) {
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
    pic <- channel_profile()$profile_pic
    if (is.null(pic) || length(pic) == 0 || isTRUE(is.na(pic))) {
      return(
        tags$div(
          class = "text-muted text-center",
          style = "border-radius: 10px; background-color: #f0f0f0; padding: 2rem 0;",
          icon("user", lib = "font-awesome")
        )
      )
    }
    tags$img(
      src = pic,
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
