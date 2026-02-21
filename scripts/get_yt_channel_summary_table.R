# Collect the data table from BigQuery
library(bigrquery)
library(DBI)

get_yt_channel_summary_table <- function(connection) {
  q <- 'SELECT
          dims.handle,
          dims.title,
          dims.join_date,
          metrics.subscriber_count,
          metrics.video_count,
          metrics.view_count
        FROM `yt_sailing_data.channel_dimensions` AS dims
        LEFT JOIN `yt_sailing_data.daily_metrics` AS metrics
          ON dims.id = metrics.channel_id
        WHERE metrics.date = (SELECT MAX(date) FROM `yt_sailing_data.daily_metrics`)
        ORDER BY metrics.subscriber_count DESC;'
  
  summary_table <- dbGetQuery(connection, q)
  
  summary_table
}