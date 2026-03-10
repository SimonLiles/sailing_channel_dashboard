#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

# Refer to this article for building the dashboard
# https://medium.com/@hdpoorna/deploying-an-r-shiny-dashboard-on-gcp-cloud-run-c1c32a076783 

library(shiny)
library(reactable)
library(bslib)
library(shinycssloaders)

# Data retrieval and handling
library(bigrquery)
library(bigrquerystorage)
library(DBI)
library(googleCloudStorageR)
library(pool)
library(tidyverse)

# Plotting
library(ggplot2)
library(plotly)
library(ggthemes)
library(scales)

library(here)

source(here("scripts", "run_sql.R"))

#initialize big query connection
# message('Initializing BigQuery connection...')

# Authenticate
message("Authenticating...")
if (Sys.getenv("SHINY_ENV") == "production") {
  # Cloud Run: use Application Default Credentials injected by the runtime
  bq_auth()
  googleAuthR::gar_gce_auth()
} else {
  # Local development: use explicit service account key file
  service_account_path <- here(Sys.getenv("SHINY_SERVICE_ACCOUNT_PATH"))
  bq_auth(path = service_account_path)
  gcs_auth(json_file = service_account_path)
}
gcs_global_bucket("yt-sailing-dashboard-cache")
message("\tAuthenticated")

project <- "yt-sailing-dashboard"
dataset <- "yt_sailing_data"

# GCS cache helpers ####
read_rds_from_gcs <- function(gcs_name) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  gcs_get_object(gcs_name, saveToDisk = tmp, overwrite = TRUE)
  readRDS(tmp)
}

gcs_cache_last_modified <- function(gcs_name) {
  meta <- gcs_get_object(gcs_name, meta = TRUE)
  meta$updated
}

# Load initial data from GCS (fast — no BigQuery on startup) ####
message("Loading data from GCS cache...")
global_summary  <- read_rds_from_gcs("cache/global_summary.rds")
leaderboard_30d <- read_rds_from_gcs("cache/leaderboard_30d.rds")
channel_lookup  <- read_rds_from_gcs("cache/channel_lookup.rds")
message("Data loaded.")

# Per-channel BigQuery query helper ####
# Fresh connection per call — immune to idle stale connection issues.
# bq_auth() above means authentication is already cached for the process;
# only the TCP connection is new each time, which BigQuery establishes quickly.
run_channel_query <- function(sql_path, params = NULL) {
  con <- dbConnect(
    bigrquery::bigquery(),
    project = project,
    dataset = dataset,
    billing = project
  )
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, read_sql(sql_path), params = params)
}

format_youtube_style <- function(n) {
  case_when(
    is.na(n)        ~ "N/A",
    n < 1000        ~ formatC(n, format = "d", big.mark = ","),
    n < 10000       ~ paste0(round(n / 1000, 2), "K"),
    n < 100000      ~ paste0(round(n / 1000, 1), "K"),
    n < 1000000     ~ paste0(round(n / 1000, 0), "K"),
    n < 10000000    ~ paste0(round(n / 1000000, 2), "M"),
    n < 100000000   ~ paste0(round(n / 1000000, 1), "M"),
    TRUE            ~ paste0(round(n / 1000000, 0), "M")
  )
}

# UI Code: Define frontend, user interface ####
ui <- page_navbar(
  theme = bs_theme(
    version = 5,
    bootswatch = "yeti", # Options: "yeti" (nautical), "flatly", "darkly"
    primary = "#002B5B"
  ),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")
  ),
  
  
  title = "Sailing Creator Analytics",
  fillable = FALSE,
  
  # Niche Pulse Page ####
  nav_panel('Niche Pulse',
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
          # Column Selection
          radioButtons(
            inputId = "macro_plot_column_selection",
            label = "Column Selection",
            choices = c("Daily Views", 
                        "7 Day Average Views",
                        # "Average Daily Views",
                        "Daily Views Growth %", 
                        "Daily Sub Growth", 
                        # "Average Daily Sub Growth",
                        "Active Channels")
          ),
          
          #Date Selection
          dateRangeInput(
            inputId = "macro_plot_date_range",
            label = "Date Range",
            start = Sys.Date() - 365,
            end = Sys.Date() + 1,
            max = Sys.Date() + 1,
          ),
          
          # End Date Selection
        ),
        plotlyOutput("macro_trend_plot"),
      ),
    ),
  ), # End of Niche Pulse Page
  
  # Creator Explorer Page ####
  nav_panel('Creator Explorer',
    # The Search Bar (always visible at the top)
    fluidRow(
      column(12, align = "center",
       selectizeInput("selected_channel", "Search for a Channel:", 
                        choices = NULL,
                        options = list(
                          placeholder = 'Type a channel name...', 
                          allowClear = TRUE,
                          minLength = 3,
                          maxOptions = 10
                        ),
                      ),
      ),
    ), # End of Search bar
    
    # The Data Area (Hidden until a channel is selected)
    withSpinner(
      uiOutput("channel_dashboard_ui"),
      type = 8,
      color = "#002B5B",
      caption = "Loading channel data..."
    ),
  ), # End of Creator Explorer page
  
  # The Leaderboard Page ####
  nav_panel('The Leaderboard',
    radioButtons("leaderboard_rank_by",
      label = "Rank By:",
      choices = c("Subscribers", "Total Views", "Videos", "Views (30d)",
                  "7D Avg Views", "Sub Growth (30d)", "Views/Video (30d)", 
                  "Views/Sub (30d)"),
      inline = TRUE,
      selected = "Views (30d)"
    ),
    uiOutput("leaderboard_reactable")
  ), # End of Leaderboard page
  
  # Growth Benchmarks Page ####
  nav_panel('Growth Benchmarks',
    # The Search Bar (always visible at the top)
    fluidRow(
      column(12, align = "center",
        selectizeInput("selected_channel_benchmarks", "Search for a Channel:", 
                        choices = NULL,
                        options = list(
                          placeholder = 'Type a channel name...', 
                          allowClear = TRUE,
                          minLength = 3,
                          maxOptions = 10
                        ),
        ),
      ),
    ), # End of Search bar
    
    # The Data Area (Hidden until a channel is selected)
    uiOutput("growth_metrics_ui"),
  ), # End of Growth Metrics page
  
  # Footer ####
  footer = card(
    fluidRow(
      column(
        width = 4,
        a("Built by Simon Liles", href = "https://quantknot.com/about-simon-2/"),
        br(),
        a("Privacy", href = "https://quantknot.com/privacy-policy/")
      ),
      
      column(
        width = 4,
        p("Don't see your channel?"),
        a("Request to add a channel here", href = "https://quantknot.com/sailing-creator-dashboard-new-channel-request/")
      ),
      
      column(
        width = 4,
        p("Data updated daily via automated GCP pipeline."),
        a("View source on Github.", 
          href = "https://github.com/SimonLiles/sailing_channel_dashboard"),
        p("Data provided by YouTube. Analysis & Metrics © 2026 Simon Liles."),
        a("Methodology & Terms", href = "https://quantknot.com/sailing-creator-analytics-methodology-attribution/")
      )
    )
  )
)

# server code: Define backend and functionality ####
server <- function(input, output, session) {
  message("Server restarted")
  observe({
    print(paste("Selected Channel ID:", input$selected_channel_benchmarks))
  })
  
  # Reactive Poll to update server data ####
  app_data_poll <- reactivePoll(
    intervalMillis = 3600000,
    session = session,
    checkFunc = function() {
      # Lightweight metadata request — no BigQuery, no pool
      message("Checking GCS cache freshness...")
      gcs_cache_last_modified("cache/global_summary.rds")
    },
    valueFunc = function() {
      message("♻️ Fresh cache detected — reloading from GCS...")
      t <- system.time({
        gs  <- read_rds_from_gcs("cache/global_summary.rds")
        lb  <- read_rds_from_gcs("cache/leaderboard_30d.rds")
        cl  <- read_rds_from_gcs("cache/channel_lookup.rds")
      })
      message(paste("GCS reload took", t["elapsed"], "seconds"))
      list(
        global_summary_pull  = gs,
        leaderboard_30d_pull = lb,
        channel_lookup_pull  = cl
      )
    }
  )
  
  observe({
    app_data <- app_data_poll()
    
    global_summary <<- app_data$global_summary_pull
    leaderboard_30d <<- app_data$leaderboard_30d_pull
    channel_lookup <<- app_data$channel_lookup_pull
    
    message("✅ Global variables refreshed in background.")
  })
  
  # Render Global Summary Data ####
  output$new_views_24h <- renderText(formatC(global_summary$latest_views[1], format="d", big.mark=","))

  output$avg_new_views_7d <- renderText(formatC(global_summary$views_moving_avg_7d[1], format="d", big.mark=","))
  
  output$view_growth_pct <- renderText(
    paste0(formatC(global_summary$view_growth_pct[1], format="d", big.mark=","), "%")
  )
  
  # new_views_24h_color <- ifelse(global_summary$view_growth_pct[1] >= 0, "green", "red")

  output$new_subs_24h <- renderText(formatC(global_summary$latest_subs[1], format="d", big.mark=",")) 
  
  output$active_channels <- renderText(formatC(global_summary$active_channels[1], format="d", big.mark=",")) 

  output$avg_daily_views <- renderText(paste("Average New Views (Last 24h):", 
                                             formatC(global_summary$avg_daily_views[1], format="d", big.mark=","))) 

  output$avg_daily_subs <- renderText(paste("Average New Subscribers (Last 24h):", 
                                            formatC(global_summary$avg_daily_subs[1], format="d", big.mark=","))) 
  
  ## Render Macro Trend Plot ####
  output$macro_trend_plot <- renderPlotly({
    # Filter for date selection
    global_summary_filtered <- global_summary %>%
      filter(date >= input$macro_plot_date_range[1] &
               date <= input$macro_plot_date_range[2])
      
    # Select data column
    switch (input$macro_plot_column_selection,
      "Daily Views" = {
        global_summary_filtered$data <- global_summary_filtered$latest_views
      },
      "7 Day Average Views" = {
        global_summary_filtered$data <- global_summary_filtered$views_moving_avg_7d
      },
      # "Average Daily Views" = {
      #   global_summary_filtered$data <- global_summary_filtered$avg_daily_views
      # },
      "Daily Views Growth %" = {
        global_summary_filtered$data <- global_summary_filtered$view_growth_pct
      },
      "Daily Sub Growth" = {
        global_summary_filtered$data <- global_summary_filtered$latest_subs
      },
      # "Average Daily Sub Growth" = {
      #   global_summary_filtered$data <- global_summary_filtered$avg_daily_subs
      # },
      "Active Channels" = {
        global_summary_filtered$data <- global_summary_filtered$active_channels
      },
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
  
  # Render Leader Board Data ####
  ## Column Selection ####
  channel_dim_cols <- c("profile_pic", "channel_title", "channel_handle",
                        "subscriber_count", "view_count", "video_count", 
                        "total_views_30d", "views_moving_avg_7d", "total_subs_30d",
                        "views_per_vid_30d", "views_per_sub_30d")
  
  rank_subs_cols <- c("sub_rank", channel_dim_cols)
  rank_lifetime_views_cols <- c("lifetime_view_rank", channel_dim_cols)
  rank_video_count_cols <- c("video_count_rank", channel_dim_cols)
  rank_views_cols <- c("view_rank", channel_dim_cols)
  rank_view_7d_avg_cols <- c("view_7d_avg_rank", channel_dim_cols)
  rank_daily_sub_cols <- c("daily_sub_rank", channel_dim_cols)
  rank_view_per_vid_30d_cols <- c("views_per_vid_30d_rank", channel_dim_cols)
  rank_view_per_sub_cols <- c("views_per_sub_30d_rank", channel_dim_cols)
  
  column_selection <- rank_views_cols
  
  
  ## Build the leaderboard table ####
  output$leaderboard_reactable <- renderUI({
    switch(input$leaderboard_rank_by,
           "Subscribers"      = { column_selection <- rank_subs_cols },
           "Total Views"      = { column_selection <- rank_lifetime_views_cols },
           "Videos"           = { column_selection <- rank_video_count_cols },
           "Views (30d)"      = { column_selection <- rank_views_cols },
           "7D Avg Views"     = { column_selection <- rank_view_7d_avg_cols },
           "Sub Growth (30d)" = { column_selection <- rank_daily_sub_cols },
           "Views/Video (30d)"= { column_selection <- rank_view_per_vid_30d_cols },
           "Views/Sub (30d)"  = { column_selection <- rank_view_per_sub_cols }
    )
    
    leaderboard_30d_sorted <- leaderboard_30d %>%
      select(all_of(column_selection)) %>%
      arrange(pick(1))
    
    # colDefs defined here so cell renderers can close over leaderboard_30d_sorted
    channel_dimensions_colDefs <- list(
      profile_pic = colDef(
        name = "",
        maxWidth = 60,
        cell = function(value) {
          tags$img(
            src = value,
            height = "40px",
            width = "40px",
            style = "border-radius: 50%; object-fit: cover;"
          )
        }
      ),
      channel_title       = colDef(name = "Creator"),
      channel_handle      = colDef(name = "Handle"),
      subscriber_count    = colDef(
        name = "Subscribers",
        align = "right",
        cell = function(value) {
          if (value < 1000) {
            formatC(value, format = "d", big.mark = ",")
          } else {
            paste0("~", format_youtube_style(value))
          }
        }
      ),
      view_count          = colDef(name = "Total Views",       format = colFormat(separators = TRUE)),
      video_count         = colDef(name = "Videos",            format = colFormat(separators = TRUE)),
      total_views_30d     = colDef(name = "Views (30d)",       format = colFormat(separators = TRUE)),
      views_moving_avg_7d = colDef(name = "7D Avg Views",      format = colFormat(separators = TRUE)),
      total_subs_30d      = colDef(
        name = "Sub Growth (30d)",
        align = "right",
        cell = function(value, index) {
          sub_count <- leaderboard_30d_sorted$subscriber_count[index]
          if (sub_count < 1000) {
            formatC(value, format = "d", big.mark = ",")
          } else if (value == 0) {
            paste0("< ", formatC(
              10 ^ (floor(log10(sub_count)) - 2),
              format = "d", big.mark = ","
            ))
          } else {
            paste0("~", formatC(value, format = "d", big.mark = ","))
          }
        }
      ),
      views_per_vid_30d   = colDef(name = "Views/Video (30d)", format = colFormat(separators = TRUE)),
      views_per_sub_30d   = colDef(name = "Views/Sub (30d)",   format = colFormat(separators = TRUE))
    )
    
    leaderboard_colDefs <- switch(input$leaderboard_rank_by,
                                  "Subscribers"       = c(list(sub_rank           = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "Total Views"       = c(list(lifetime_view_rank  = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "Videos"            = c(list(video_count_rank    = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "Views (30d)"       = c(list(view_rank           = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "7D Avg Views"      = c(list(view_7d_avg_rank    = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "Sub Growth (30d)"  = c(list(daily_sub_rank      = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "Views/Video (30d)" = c(list(views_per_vid_30d_rank = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs),
                                  "Views/Sub (30d)"   = c(list(views_per_sub_30d_rank = colDef(name = "Rank", maxWidth = 100)), channel_dimensions_colDefs)
    )
    
    output$leaderboard_table <- renderReactable({
      reactable(
        leaderboard_30d_sorted,
        columns = leaderboard_colDefs,
        highlight = TRUE,
        striped = TRUE,
        searchable = TRUE,
        filterable = FALSE,
        showPageSizeOptions = TRUE,
        compact = FALSE,
      )
    })
    
    tagList(
      reactableOutput("leaderboard_table"),
      tags$p(
        class = "text-muted fst-italic mt-2 px-1 small",
        "† Subscriber Count and Sub Growth (30d) are subject to YouTube's API 
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
  
  # Get and Render Channel Explorer data ####
  # Load the search bar with channels as user searches
  
  # Selectize for Creator Explorer page
  updateSelectizeInput(
    session,
    "selected_channel",
    selected = character(0),
    choices = setNames(channel_lookup$channel_id, channel_lookup$channel_title),
    server = TRUE
  )
  
  # observeEvent(input$selected_channel, {
  #   selected_channel <- input$selected_channel
  #   if(input$selected_channel != input$selected_channel_benchmarks) {
  #     updateSelectizeInput(session, 
  #                          "selected_channel_benchmarks", 
  #                          choices = setNames(channel_lookup$channel_id, channel_lookup$channel_title), 
  #                          server = TRUE,
  #                          selected = input$selected_channel)
  #   }
  # }, ignoreInit = TRUE)
  # 
  # observeEvent(input$selected_channel_benchmarks, {
  #   selected_channel <- input$selected_channel_benchmarks
  #   if(input$selected_channel_benchmarks != input$selected_channel) {
  #     updateSelectizeInput(session, 
  #                          "selected_channel", 
  #                          choices = setNames(channel_lookup$channel_id, channel_lookup$channel_title), 
  #                          server = TRUE,
  #                          selected = input$selected_channel_benchmarks)
  #   }
  # }, ignoreInit = TRUE)
  
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
  
  # Create the layout for the channel explorer page ####
  output$channel_dashboard_ui <- renderUI({
    req(input$selected_channel)

    ### Time Series Plots ####
    output$subscriber_count_ts_plot <- renderPlotly({
      plot_ly(channel_history()) %>%
        add_lines(
          x = ~date, y = ~subscriber_count,
          color = I("black"), span = I(1),
          fill = 'tozeroy', alpha = 0.2
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
          fill = 'tozeroy', alpha = 0.2
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
          fill = 'tozeroy', alpha = 0.2
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
          fill = 'tozeroy', alpha = 0.2
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
      fluidRow(
        ### About the channel ####
        column(
          width = 6,
          fluidRow(
            # Profile Picture
            column(
              width = 2,
              htmlOutput("profile_card"),
            ),
            column(
              width = 5,
              h2(channel_profile()$channel_title), 
              p(channel_profile()$channel_handle), 
              p(paste("Joined:", channel_profile()$join_date)),
            ),
            column(
              width = 3, 
              actionButton(
                "channel_link", 
                label = "Find on YouTube",
                icon = icon("external-link-alt"),
                onclick = paste0("window.open('https://www.youtube.com/", 
                  channel_profile()$channel_handle, "', '_blank');"
                ),
              )
            )
          ),
          # About the channel
          br(),
          h3("About:"),
          p(channel_profile()$channel_description),
        ),
        
        ### Primary Metrics ####
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
      
      ### 2nd Row ####
      fluidRow(
        #### Tag Cloud ####
        column(
          width = 6,
          card(
            card_header(
              "Channel Tags"
            ),
            htmlOutput("keyword_pills"),
          )
        ),
        #### Interactive Plot? ####
        column(
          width = 6,
        ),
      ),
      
      # Negative value footnote — only renders when relevant
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
  
  ## Render the Channel Explorer Page ####
  output$profile_card <- renderUI({
    req(channel_profile())
    tags$img(src = channel_profile()$profile_pic, width = "100%", style = "border-radius: 10px;")
  })
  
  ## Render keyword pills ####
  output$keyword_pills <- renderUI({
    # Get the data from your reactive profile query
    profile <- channel_profile()
    req(profile$channel_keywords)
    
    keywords <- str_extract_all(profile$channel_keywords, '"[^"]+"|[\\S]+')[[1]]
    
    keywords <- gsub('\"', '', keywords)
    keywords <- gsub(',', '', keywords)
    keywords <- trimws(keywords)
    keywords <- keywords[keywords != ""]
    
    # keywords <- head(keywords, 12)
    
    # 4. Map the strings to HTML spans
    tagList(
      tags$div(
        class = "pill-container",
        lapply(keywords, function(k) {
          tags$span(class = "keyword-pill", k)
        })
      ),
    )
  })
  
  # Get Growth Benchmarks ####
  # Load the search bar with channels as user searches
  updateSelectizeInput(
    session, 
    "selected_channel_benchmarks", 
    selected = character(0),
    choices = setNames(channel_lookup$channel_id, channel_lookup$channel_title), 
    server = TRUE
  )
  
  channel_growth_metrics <- reactive({
    # This acts as the bouncer. If nothing is selected, STOP and show nothing.
    req(input$selected_channel_benchmarks) 
    
    leaderboard_30d %>%
      filter(channel_id == input$selected_channel_benchmarks)
  })
  
  output$growth_metrics_ui <- renderUI({
    req(input$selected_channel_benchmarks)
    
    fluidPage(
      # Channel Identifiers
      fluidRow(
        h1(channel_growth_metrics()$channel_title)
      ),
      
      ### Top Metrics in Value Boxes ####
      layout_columns(
        fill = FALSE,
        value_box(
          title = "Views past 30 days",
          value = channel_growth_metrics()$total_views_30d,
          h5(paste0(channel_growth_metrics()$view_percentile,
                   "th percentile")),
          fill = FALSE
        ),
        value_box(
          title = "7 Day Average Views",
          value = channel_growth_metrics()$views_moving_avg_7d,
          h5(paste0(channel_growth_metrics()$view_7d_avg_percentile,
                   "th percentile")),
          fill = FALSE
        ),
        value_box(
          title = "New Subscribers past 30 days",
          value = channel_growth_metrics()$daily_new_subs,
          h5(paste0(channel_growth_metrics()$daily_sub_percentile,
                   "th percentile")),
          fill = FALSE
        ),
        value_box(
          title = "Catalog Yield",
          value = channel_growth_metrics()$views_per_vid_30d,
          h5(paste0(channel_growth_metrics()$views_per_vid_30d_percentile,
                   "th percentile")),
          p("Views per Video past 30 days"),
          fill = FALSE
        ),
        value_box(
          title = "Audience Activation",
          value = channel_growth_metrics()$views_per_sub_30d,
          h5(paste0(channel_growth_metrics()$views_per_sub_30d_percentile,
                   "th percentile")),
          p("Views per Subscriber past 30 days"),
          fill = FALSE
        ),
      ),
      
      ### Algorithmic Performance Charts ####
      card(
        card_header("Algorithmic Performance"),
        # Render the plot
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
        
        # Plot Explanation
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
      
      ### Audience Activation Chart ####
      card(
        card_header("Audience Activation"),
        card(
          plotlyOutput("audience_activation_30d_chart"),
          full_screen = TRUE, 
          fill = TRUE
        ),
        
        # Plot Explanation
        p("Plotted above is the audience activation against the subscriber count
          of active channels. Both axes have log 10 scales to group the data into
          a more easily read format. In general, healthy channels have an audience
          activation of 0.5 to 1 which indicates a healthy base of returning viewers.
          Values greater than 1 can also indicate growth if there is also a 
          corresponding and current growth in subscribers.")
      )
    )
  })
  
  ## Make the Growth Metric Plots ####
  output$algorithm_performance_chart <- renderPlotly(
    ggplotly(
      tooltip = "text",
      
      ggplot(leaderboard_30d, 
             aes(x = subscriber_count, y = lifetime_views_per_vid)
             ) + 
        geom_point(alpha = 1, color = "black", aes(text = channel_handle)) + 
        geom_smooth(method = "lm") +
        annotate(geom = "point", x = channel_growth_metrics()$subscriber_count, 
                 y = channel_growth_metrics()$lifetime_views_per_vid,
                 text = channel_growth_metrics()$channel_handle, color = "red", 
                 size = 3, shape = "star") +
        scale_x_log10(labels = label_number()) +
        scale_y_log10(labels = label_number()) +
        ggtitle("Channel Performance, Lifetime Views per Video x Subscriber Count, log 10 scales") + 
        labs(x = "Subscriber Count", y = "Views per Video (Lifetime)") +
        theme_minimal() +
        theme(
              legend.position = "left",
              # panel.grid.minor.x = element_line(color = "grey", linetype = "dotted", linewidth = 0.2)
              )
      )
  )
  
  output$algorithm_performance_30d_chart <- renderPlotly(
    ggplotly(
      tooltip = "text",
      
      ggplot(leaderboard_30d, 
             aes(x = subscriber_count, y = views_per_vid_30d)
      ) + 
        geom_point(alpha = 1, color = "black", aes(text = channel_handle)) + 
        geom_smooth(method = "lm") +
        annotate(geom = "point", x = channel_growth_metrics()$subscriber_count, 
                 y = channel_growth_metrics()$views_per_vid_30d,
                 text = channel_growth_metrics()$channel_handle, color = "red", 
                 size = 3, shape = "star") +
        scale_x_log10(labels = label_number()) +
        scale_y_log10(labels = label_number()) +
        ggtitle("Channel Performance, 30 Day Views per Video x Subscriber Count, log 10 scales") + 
        labs(x = "Subscriber Count", y = "Views per Video (30 Days)") +
        theme_minimal() +
        theme(
          legend.position = "left",
          # panel.grid.minor.x = element_line(color = "grey", linetype = "dotted", linewidth = 0.2)
        )
    )
  )
  
  output$audience_activation_30d_chart <- renderPlotly(
    ggplotly(
      tooltip = "text",
      
      ggplot(leaderboard_30d, 
             aes(x = subscriber_count, y = views_per_sub_30d)
      ) + 
        geom_point(alpha = 1, color = "black", aes(text = channel_handle)) + 
        geom_smooth(method = "lm") +
        annotate(geom = "point", x = channel_growth_metrics()$subscriber_count, 
                 y = channel_growth_metrics()$views_per_sub_30d,
                 text = channel_growth_metrics()$channel_handle, color = "red", 
                 size = 3, shape = "star") +
        scale_x_log10(labels = label_number()) +
        scale_y_log10(labels = label_number()) +
        ggtitle("Audience Activation, 30 Day Views per Subscriber x Subscriber Count, log 10 scales") + 
        labs(x = "Subscriber Count", y = "Views per Subscriber (30 Days)") +
        theme_minimal() +
        theme(
          legend.position = "left",
          # panel.grid.minor.x = element_line(color = "grey", linetype = "dotted", linewidth = 0.2)
        )
    )
  )
}

# Run the application 
shinyApp(ui = ui, server = server)
