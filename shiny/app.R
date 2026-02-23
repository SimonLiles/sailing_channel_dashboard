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

# Define UI for application that draws a histogram
ui <- page_navbar(
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")
  ),
  
  title = "YouTube Sailing Channels Analytics",
  
  # Niche Pulse Page ####
  nav_panel('Niche Pulse',
    # Summary Stats
    layout_columns(
      fill = FALSE,
      value_box(
        title = "New Views (Last 24h)",
        value = textOutput("new_views_24h"),
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
      card_header("Macro Trend Plot"),
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
                        "Daily Views Growth %", 
                        "Daily Sub Growth", 
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
    reactableOutput("leaderboard_table"),
  ), # End of Leaderboard page
  
  # Growth Benchmarks Page ####
  nav_panel('Growth Benchmarks',
  ), # End of Algorithm Performance page
)

# Define server logic required to draw a histogram
server <- function(input, output, session) {
  observe({
    print(paste("Selected Channel ID:", input$selected_channel))
  })
  
  # Render Global Summary Data ####
  output$new_views_24h <- renderText(formatC(global_summary$latest_views[1], format="d", big.mark=","))

  output$view_growth_pct <- renderText(
    paste0(formatC(global_summary$view_growth_pct[1], format="d", big.mark=","), "%")
  )
  
  new_views_24h_color <- ifelse(global_summary$view_growth_pct[1] >= 0, "green", "red")

  output$new_subs_24h <- renderText(formatC(global_summary$latest_subs[1], format="d", big.mark=",")) 
  
  output$active_channels <- renderText(formatC(global_summary$active_channels[1], format="d", big.mark=",")) 
  
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
      "Daily Views Growth %" = {
        global_summary_filtered$data <- global_summary_filtered$view_growth_pct
      },
      "Daily Sub Growth" = {
        global_summary_filtered$data <- global_summary_filtered$latest_subs
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
  output$leaderboard_table <- renderReactable({
    reactable(
      leaderboard_30d,
      columns = list(
        view_rank = colDef(
          name = "View Rank",
          maxWidth = 100
        ),
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
        total_views_30d = colDef(name = "Views (30d)", format = colFormat(separators = TRUE)),
        total_subs_30d = colDef(name = "Subscribers (30d)", format = colFormat(separators = TRUE)),
        sub_conversion_rate = colDef(name = "Conversion Rate\n(subs / 1,000 views)", format = colFormat(digits = 2))
      ),
      highlight = TRUE,
      striped = TRUE,
      searchable = TRUE,
      filterable = FALSE,
      showPageSizeOptions = TRUE,
      compact = FALSE,
    )
  })
  
  # Get and Render Channel Explorer data ####
  # Load the search bar with channels as user searches
  updateSelectizeInput(
    session, 
    "selected_channel", 
    choices = setNames(channel_lookup$channel_id, channel_lookup$channel_title), 
    server = TRUE
  )
  
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
}

# Run the application 
shinyApp(ui = ui, server = server)
