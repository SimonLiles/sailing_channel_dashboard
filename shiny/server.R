server <- function(input, output, session) {
  message("Server started")

  # Reactive poll to refresh cached data hourly ----
  app_data_poll <- reactivePoll(
    intervalMillis = 3600000,
    session = session,
    checkFunc = function() {
      message("Checking GCS cache freshness...")
      gcs_cache_last_modified(paste0(config_get("gcs_cache_prefix", "cache"), "/global_summary.rds"))
    },
    valueFunc = function() {
      message("Fresh cache detected — reloading from GCS...")
      t <- system.time({
        gcs_prefix <- config_get("gcs_cache_prefix", "cache")
        gs <- read_rds_from_gcs(paste0(gcs_prefix, "/global_summary.rds"))
        lb <- read_rds_from_gcs(paste0(gcs_prefix, "/leaderboard_rankings.rds"))
        ci <- read_rds_from_gcs(paste0(gcs_prefix, "/channel_info.rds"))
      })
      message(paste("GCS reload took", t["elapsed"], "seconds"))
      list(
        global_summary_pull       = gs,
        leaderboard_rankings_pull = lb,
        channel_info_pull         = ci
      )
    }
  )

  observe({
    app_data <- app_data_poll()
    global_summary       <<- app_data$global_summary_pull
    leaderboard_rankings <<- app_data$leaderboard_rankings_pull
    channel_info         <<- app_data$channel_info_pull
    message("Global variables refreshed in background.")
  })

  # Delegate to page servers ----
  niche_pulse_server(input, output, session)
  creator_explorer_server(input, output, session)
  leaderboard_server(input, output, session)
  growth_benchmarks_server(input, output, session)
}
