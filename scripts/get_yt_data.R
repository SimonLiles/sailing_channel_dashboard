# Function to pull channel data from YouTube Data API v3

require(httr)
require(jsonlite)
require(dplyr)

get_yt_data <- function(channel_handle) {
  message(paste('Querying:', channel_handle))
  
  # Retrieve the key from the environment
  yt_data_api_key <- Sys.getenv("YT_API_KEY")
  
  if (yt_key == "") {
    stop("API Key not found! Ensure YT_API_KEY is set in environment.")
  }
  
  #Base Query variables
  base <- "https://www.googleapis.com/youtube/v3/"
  
  channelIDs <- channels$id
  handles <- channels$handle
  
  today <- as.character(date())
  
  search_type <- "channel"
  max_results <- 1
  time_after_base <- "-01-01T00%3A00%3A00Z"
  time_before_base <- "-12-31T23%3A59%3A59Z"
  
  # Query variables
  parts <- paste("snippet", "statistics", "brandingSettings",
                 sep = ",")
  
  #Build the parameter list
  q_channels_param <- paste(paste0("key=", yt_data_api_key),
                            paste0("id=", channel_handle),
                            paste0("part=", parts),
                            sep = "&")
  
  # Build query
  api_call_channels <- paste0(base, "channels", "?", q_channels_param)
  
  # Perform data query
  api_result_channels <- GET(api_call_channels)
  json_result_channels <- content(api_result_channels, "text", encoding = "UTF-8")
  
  # Read raw input
  result_channels <- fromJSON(json_result_channels, flatten = TRUE)
  
  # Parse data
  channel_data <- result_channels$items
  
  if(is.null(channel_data)) {
    message("channel: ", channel_handle, " is null", appendLF = FALSE)
  }
  
  if(channel_data$statistics.hiddenSubscriberCount == TRUE) {
    channel_data$statistics.subscriberCount = NA
  }
  
  data.frame(channel_handle,
             channel_data$id, 
             channel_data$snippet.title, 
             channel_data$snippet.description, 
             channel_data$snippet.publishedAt, 
             channel_data$statistics.viewCount, 
             channel_data$statistics.videoCount, 
             channel_data$statistics.subscriberCount, 
             channel_data$statistics.hiddenSubscriberCount)
}
