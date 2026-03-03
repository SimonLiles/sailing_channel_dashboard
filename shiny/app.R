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
library(DBI)
library(tidyverse)

# Plotting
library(ggplot2)
library(plotly)
library(ggthemes)
library(scales)

library(here)

source(here("scripts", "run_sql.R"))

#initialize big query connection
message('Initializing BigQuery connection...')

# Authenticate
service_account_path <- here(Sys.getenv("SHINY_SERVICE_ACCOUNT_PATH"))
bq_auth(path = service_account_path)

project <- "yt-sailing-dashboard"
dataset <- "yt_sailing_data"

# Make connection
connection <- dbConnect(
  bigrquery::bigquery(),
  project = project,
  dataset = dataset,
  billing = project
)

message('\tConnected to BigQuery')

global_summary <- dbGetQuery(connection, 
                             read_sql(here("sql", "04_apps", "get_global_summary.sql")))

leaderboard_30d <- dbGetQuery(connection, 
                              read_sql(here("sql", "04_apps", "get_leaderboard_30d.sql")))

channel_lookup <- dbGetQuery(connection,
                             read_sql(here("sql", "04_apps", "get_channel_lookup.sql")))

# UI Code: Define frontend, user interface
ui <- page_navbar(
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")
  ),
  
  title = "Sailing Creator Analytics",
  
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
        sidebar = sidebar(
          title = "Plot Controls",
          position = "left",
          width = "20%",
          # Column Selection
          radioButtons(
            inputId = "macro_plot_column_selection",
            label = "Column Selection",
            choices = c("Daily Views", 
                        "Average Daily Views",
                        "Daily Views Growth %", 
                        "Daily Sub Growth", 
                        "Average Daily Sub Growth",
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
        plotOutput("macro_trend_plot"),
      ),
    ),
  ), # End of Niche Pulse Page
  
  # Creator Explorer Page ####
  nav_panel('Creator Explorer',
    # The Search Bar (always visible at the top)
    fluidRow(
      column(12, align = "center",
       selectizeInput("selected_channel", "Search for a Channel:", 
                        choices = "",
                        selected = "",
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
    uiOutput("channel_dashboard_ui"),
  ), # End of Creator Explorer page
  
  # The Leaderboard Page ####
  nav_panel('The Leaderboard',
    radioButtons("leaderboard_rank_by",
      label = "Rank By:",
      choices = c("Subscribers", "Lifetime Views", "Video Count", "Views (30d)",
                  "7 Day Avg Views", "Subscriber Growth (30d)"),
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
                        choices = "",
                        selected = "",
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
  ), # End of Algorithm Performance page
)

# server code: Define backend and functionality
server <- function(input, output, session) {
  observe({
    print(paste("Selected Channel ID:", input$selected_channel_benchmarks))
  })
  
  # Render Global Summary Data ####
  output$new_views_24h <- renderText(formatC(global_summary$latest_views[1], format="d", big.mark=","))

  output$view_growth_pct <- renderText(
    paste0(formatC(global_summary$view_growth_pct[1], format="d", big.mark=","), "%")
  )
  
  new_views_24h_color <- ifelse(global_summary$view_growth_pct[1] >= 0, "green", "red")

  output$new_subs_24h <- renderText(formatC(global_summary$latest_subs[1], format="d", big.mark=",")) 
  
  output$active_channels <- renderText(formatC(global_summary$active_channels[1], format="d", big.mark=",")) 

  output$avg_daily_views <- renderText(paste("Average New Views (Last 24h):", 
                                             formatC(global_summary$avg_daily_views[1], format="d", big.mark=","))) 

  output$avg_daily_subs <- renderText(paste("Average New Subscribers (Last 24h):", 
                                            formatC(global_summary$avg_daily_subs[1], format="d", big.mark=","))) 
  
  ## Render Macro Trend Plot ####
  output$macro_trend_plot <- renderPlot({
    # Filter for date selection
    global_summary_filtered <- global_summary %>%
      filter(date >= input$macro_plot_date_range[1] &
               date <= input$macro_plot_date_range[2])
      
    # Select data column
    switch (input$macro_plot_column_selection,
      "Daily Views" = {
        global_summary_filtered$data <- global_summary_filtered$latest_views
      },
      "Average Daily Views" = {
        global_summary_filtered$data <- global_summary_filtered$avg_daily_views
      },
      "Daily Views Growth %" = {
        global_summary_filtered$data <- global_summary_filtered$view_growth_pct
      },
      "Daily Sub Growth" = {
        global_summary_filtered$data <- global_summary_filtered$latest_subs
      },
      "Average Daily Sub Growth" = {
        global_summary_filtered$data <- global_summary_filtered$avg_daily_subs
      },
      "Active Channels" = {
        global_summary_filtered$data <- global_summary_filtered$active_channels
      },
    )
    
    ggplot(global_summary_filtered, aes(date, data)) +
      geom_line() + 
      geom_point() +
      labs(
        x = "Date",
        y = input$macro_plot_column_selection
      )
  })
  
  # Render Leader Board Data ####
  ## Column Selection ####
  channel_dim_cols <- c("profile_pic", "channel_title", "channel_handle",
                        "subscriber_count", "view_count", "video_count", "total_views_30d", "views_moving_avg_7d", "total_subs_30d")
  
  rank_subs_cols <- c("sub_rank", channel_dim_cols)
  rank_lifetime_views_cols <- c("lifetime_view_rank", channel_dim_cols)
  rank_video_count_cols <- c("video_count_rank", channel_dim_cols)
  rank_views_cols <- c("view_rank", channel_dim_cols)
  rank_view_7d_avg_cols <- c("view_7d_avg_rank", channel_dim_cols)
  rank_daily_sub_cols <- c("daily_sub_rank", channel_dim_cols)
  
  column_selection <- rank_views_cols
  
  ## Column Name Selection ####
  channel_dimensions_colDefs <- list(
    profile_pic = colDef(
      name = "", 
      maxWidth = 60,
      cell = function(value) {
        # Render the HTML image tag
        tags$img(
          src = value, 
          height = "40px", 
          width = "40px",
          style = "border-radius: 50%; object-fit: cover;" # Makes them circular
        )
      }
    ),
    channel_title = colDef(name = "Creator"),
    channel_handle = colDef(name = "Handle"), 
    
    subscriber_count = colDef(name = "Subscribers", format = colFormat(separators = TRUE)),
    view_count = colDef(name = "Lifetime View Count", format = colFormat(separators = TRUE)),
    video_count = colDef(name = "Video Count", format = colFormat(separators = TRUE)),
    
    total_views_30d = colDef(name = "Views (30d)", format = colFormat(separators = TRUE)),
    views_moving_avg_7d = colDef(name = "7 Day Avg Views", format = colFormat(separators = TRUE)),
    total_subs_30d = colDef(name = "Subscriber Growth (30d)", format = colFormat(separators = TRUE))
  )
  
  rank_subs_colDefs <- c(
    list(sub_rank = colDef(
      name = "Rank",
      maxWidth = 100
    )),
    channel_dimensions_colDefs
  )
  rank_lifetime_views_colDefs <- c(
    list(lifetime_view_rank = colDef(
      name = "Rank",
      maxWidth = 100
    )),
    channel_dimensions_colDefs
  )
  rank_video_count_colDefs <- c(
    list(video_count_rank = colDef(
      name = "Rank",
      maxWidth = 100
    )),
    channel_dimensions_colDefs
  )
  rank_views_colDefs <- c(
    list(view_rank = colDef(
      name = "Rank",
      maxWidth = 100
    )),
    channel_dimensions_colDefs
  )
  rank_view_7d_avg_colDefs <- c(
    list(view_7d_avg_rank = colDef(
      name = "Rank",
      maxWidth = 100
    )),
    channel_dimensions_colDefs
  )
  rank_daily_sub_colDefs <- c(
    list(daily_sub_rank = colDef(
      name = "Rank",
      maxWidth = 100
    )),
    channel_dimensions_colDefs
  )
  
  leaderboard_colDefs <- rank_views_cols
  
  ## Build the leaderboard table ####
  output$leaderboard_reactable <- renderUI(
    output$leaderboard_table <- renderReactable({
      switch(input$leaderboard_rank_by,
         "Subscribers" = {
           column_selection <- rank_subs_cols
           leaderboard_colDefs <- rank_subs_colDefs
         },
         "Lifetime Views" = {
           column_selection <- rank_lifetime_views_cols
           leaderboard_colDefs <- rank_lifetime_views_colDefs
         },
         "Video Count" = {
           column_selection <- rank_video_count_cols
           leaderboard_colDefs <- rank_video_count_colDefs
         },
         "Views (30d)" = {
           column_selection <- rank_views_cols
           leaderboard_colDefs <- rank_views_colDefs
         },
         "7 Day Avg Views" = {
           column_selection <- rank_view_7d_avg_cols
           leaderboard_colDefs <- rank_view_7d_avg_colDefs
         },
         "Subscriber Growth (30d)" = {
           column_selection <- rank_daily_sub_cols
           leaderboard_colDefs <- rank_daily_sub_colDefs
         }
      )
      
      leaderboard_30d_sorted <- leaderboard_30d %>%
        select(all_of(column_selection)) %>%
        arrange(pick(1))
      
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
  )
  
  # Get and Render Channel Explorer data ####
  # Load the search bar with channels as user searches
  
  # Selectize for Creator Explorer page
  updateSelectizeInput(
    session,
    "selected_channel",
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
    # This acts as the bouncer. If nothing is selected, STOP and show nothing.
    req(input$selected_channel) 
    
    dbGetQuery(connection,
               read_sql(here("sql", "04_apps", "get_channel_profile.sql")),
               params = list(id = input$selected_channel))
  })
  
  channel_history <- reactive({
    # This acts as the bouncer. If nothing is selected, STOP and show nothing.
    req(input$selected_channel) 
    
    dbGetQuery(connection,
               read_sql(here("sql", "04_apps", "get_channel_history.sql")),
               params = list(id = input$selected_channel))
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
        config(displayModeBar = F) %>%
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
        config(displayModeBar = F) %>%
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
        config(displayModeBar = F) %>%
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
        config(displayModeBar = F) %>%
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
  
  # Get Growth Benchmarks
  # Load the search bar with channels as user searches
  updateSelectizeInput(
    session, 
    "selected_channel_benchmarks", 
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
          p(paste0(channel_growth_metrics()$view_percentile,
                   "th perecentile")),
          fill = FALSE
        ),
        value_box(
          title = "7 Day Average Views",
          value = channel_growth_metrics()$views_moving_avg_7d,
          p(paste0(channel_growth_metrics()$view_7d_avg_percentile,
                   "th perecentile")),
          fill = FALSE
        ),
        value_box(
          title = "New Subscribers past 30 days",
          value = channel_growth_metrics()$daily_new_subs,
          p(paste0(channel_growth_metrics()$daily_sub_percentile,
                   "th perecentile")),
          fill = FALSE
        ),
        value_box(
          title = "Views per Video past 30 days",
          value = channel_growth_metrics()$views_per_vid_30d,
          p(paste0(channel_growth_metrics()$views_per_vid_30d_percentile,
                   "th perecentile")),
          fill = FALSE
        ),
        value_box(
          title = "Views per Subscriber past 30 days",
          value = channel_growth_metrics()$views_per_sub_30d,
          p(paste0(channel_growth_metrics()$views_per_sub_30d_percentile,
                   "th perecentile")),
          fill = FALSE
        ),
      ),
      
      ### Algorithmic Performance Chart ####
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
          all of the ponts would crowd the lower left corner, and the biggest 
          channel (Sailing La Vagabonde) would be plotted in the upper right hand
          corner. With the squeezed data, in the lifetime data, a pattern becomes
          obvious, this is YouTube's algorithmic floor. Given a channel's size, 
          it should performby at least a certain amount. "),
        fill = TRUE
      )
    )
  })
  
  output$algorithm_performance_chart <- renderPlotly(
    ggplotly(
      # tooltip = "text",
      
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
      # tooltip = "text",
      
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
}

# Run the application 
shinyApp(ui = ui, server = server)
