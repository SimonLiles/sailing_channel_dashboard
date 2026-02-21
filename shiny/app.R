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

# Data retrieval and handling
library(bigrquery)

# Plotting
library(ggplot2)

# Define UI for application that draws a histogram
ui <- fluidPage(

  # Application title
  titlePanel("Sailing YouTube Channels"),
  
  # Navigation Window
  tabsetPanel(
               tabPanel('Summary Data',
                          # Sidebar with a slider input for number of bins 
                          sidebarLayout(
                            sidebarPanel(
                              sliderInput("bins",
                                          "Number of bins:",
                                          min = 1,
                                          max = 50,
                                          value = 30)
                            ), # End of sidebar panel
                            
                            # Show a plot of the generated distribution
                            mainPanel(
                              plotOutput("distPlot")
                            ) # End of main panel
                            
                            
                          )
                        ), # End of Summary Data Page
               
               
               tabPanel('Changes over Time'
                        ), # End of timeSeries page
               
               
               ), #End navlistPanel
)

# Define server logic required to draw a histogram
server <- function(input, output, session) {
  #initialize big query connection
  message('Initializing BigQuery connection...')
  
  # Authenticate
  service_account_path <- '.config/gcloud/yt-sailing-dashboard-039b13fb9084.json'
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
  
  # Get full data table

    output$distPlot <- renderPlot({
        # generate bins based on input$bins from ui.R
        x    <- faithful[, 2]
        bins <- seq(min(x), max(x), length.out = input$bins + 1)

        # draw the histogram with the specified number of bins
        hist(x, breaks = bins, col = 'darkgray', border = 'white')
    })
}

# Run the application 
shinyApp(ui = ui, server = server)
