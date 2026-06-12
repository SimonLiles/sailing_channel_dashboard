server <- function(input, output, session) {
  message("Server started")

  # Reactive poll to refresh cached data hourly ----
  app_data_poll <- reactivePoll(
    intervalMillis = 3600000,
    session = session,
    checkFunc = function() {
      message("Checking GCS cache freshness...")
      gcs_cache_last_modified("cache/global_summary.rds")
    },
    valueFunc = function() {
      message("Fresh cache detected — reloading from GCS...")
      t <- system.time({
        gs <- read_rds_from_gcs("cache/global_summary.rds")
        lb <- read_rds_from_gcs("cache/leaderboard_30d.rds")
        cl <- read_rds_from_gcs("cache/channel_lookup.rds")
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
    global_summary  <<- app_data$global_summary_pull
    leaderboard_30d <<- app_data$leaderboard_30d_pull
    channel_lookup  <<- app_data$channel_lookup_pull
    message("Global variables refreshed in background.")
  })

  # Delegate to page servers ----
  niche_pulse_server(input, output, session)
  creator_explorer_server(input, output, session)
  leaderboard_server(input, output, session)
  growth_benchmarks_server(input, output, session)
}
