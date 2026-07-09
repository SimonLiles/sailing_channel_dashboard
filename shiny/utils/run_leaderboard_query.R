run_leaderboard_query <- function(sql_path, params = list(), raw_sql = NULL) {
  con <- dbConnect(
    bigrquery::bigquery(),
    project = project,
    dataset = dataset,
    billing = project
  )
  on.exit(dbDisconnect(con), add = TRUE)

  query <- if (!is.null(raw_sql)) raw_sql else render_sql(sql_path, project = project, dataset = dataset)

  dbGetQuery(con, query, params = params)
}

# ---- Cohorts and buckets (query mart_channel_cohorts directly) ----

# Get all (cohort_type, cohort_value) pairs for filter dropdowns
get_leaderboard_cohorts <- function() {
  run_leaderboard_query(here("sql", "04_apps", "get_leaderboard_cohorts.sql"))
}

# Get cohort values (buckets) for a given cohort type
get_leaderboard_buckets <- function(cohort_type) {
  run_leaderboard_query(
    here("sql", "04_apps", "get_leaderboard_buckets.sql"),
    params = list(cohort_type = cohort_type)
  )
}

# Get a single channel's cohort value
get_channel_cohort_value <- function(channel_id, cohort_type) {
  run_leaderboard_query(
    here("sql", "04_apps", "get_channel_cohort_value.sql"),
    params = list(channel_id = channel_id, cohort_type = cohort_type)
  )
}

# ---- Paginated leaderboard ----

# Get one page of leaderboard data using keyset pagination.
# direction: "next" (default) or "prev"
get_leaderboard_page <- function(cohort_type, cohort_value, rank_by_metric,
                                 window_days, page_size,
                                 selected_metrics,
                                 cursor_ranking = NULL,
                                 cursor_channel_id = NULL,
                                 direction = "next",
                                 search_query = NULL) {
  template <- readLines(here("sql", "04_apps", "get_leaderboard_page.sql"), warn = FALSE)
  template <- glue(
    paste(template, collapse = "\n"),
    project = project,
    dataset = dataset,
    .open = "{{", .close = "}}"
  )

  # Metric names
  metrics_quoted <- paste(shQuote(unique(selected_metrics), type = "sh"), collapse = ", ")
  template <- gsub("--METRIC_NAMES--", metrics_quoted, template, fixed = TRUE)

  # Window clause
  if (is.na(window_days)) {
    template <- gsub("--WINDOW_CLAUSE--", "r.window_days IS NULL", template, fixed = TRUE)
  } else {
    template <- gsub(
      "--WINDOW_CLAUSE--",
      "(r.window_days = @window_days OR r.window_days IS NULL)",
      template, fixed = TRUE
    )
  }

  # Cursor condition
  if (is.null(cursor_ranking) || is.null(cursor_channel_id)) {
    template <- gsub("--CURSOR_CONDITION--", "TRUE", template, fixed = TRUE)
  } else if (direction == "next") {
    template <- gsub(
      "--CURSOR_CONDITION--",
      "(r.ranking > @cursor_ranking OR (r.ranking = @cursor_ranking AND r.channel_id > @cursor_channel_id))",
      template, fixed = TRUE
    )
  } else {
    template <- gsub(
      "--CURSOR_CONDITION--",
      "(r.ranking < @cursor_ranking OR (r.ranking = @cursor_ranking AND r.channel_id < @cursor_channel_id))",
      template, fixed = TRUE
    )
  }

  # Order direction
  if (is.null(cursor_ranking) || direction == "next") {
    template <- gsub("--ORDER_DIRECTION--", "ASC", template, fixed = TRUE)
  } else {
    template <- gsub("--ORDER_DIRECTION--", "DESC", template, fixed = TRUE)
  }

  # Page size (inlined as literal because bigrquery parameter binding
  # for LIMIT clauses is unreliable)
  template <- gsub("--PAGE_SIZE--", as.character(page_size), template, fixed = TRUE)

  params <- list(
    cohort_type       = cohort_type,
    cohort_value      = cohort_value,
    rank_by_metric    = rank_by_metric,
    window_days       = if (is.na(window_days)) bigrquery::bq_param_scalar(NA, type = "INTEGER") else as.integer(window_days),
    cursor_ranking    = if (is.null(cursor_ranking)) bigrquery::bq_param_scalar(NA, type = "INTEGER") else as.integer(cursor_ranking),
    cursor_channel_id = if (is.null(cursor_channel_id)) NA_character_ else cursor_channel_id,
    search_query      = search_query %||% ""
  )

  result <- run_leaderboard_query(sql_path = NULL, params = params, raw_sql = template)

  # If navigating backward, reverse the result rows so they're in ascending order
  if (!is.null(cursor_ranking) && direction == "prev") {
    result <- result[nrow(result):1, , drop = FALSE]
  }

  result
}

# Get total channel count for the current filter set (for pagination)
get_leaderboard_count <- function(cohort_type, cohort_value, rank_by_metric,
                                  window_days, search_query = NULL) {
  template <- readLines(here("sql", "04_apps", "get_leaderboard_count.sql"), warn = FALSE)
  template <- glue(
    paste(template, collapse = "\n"),
    project = project,
    dataset = dataset,
    .open = "{{", .close = "}}"
  )

  params <- list(
    cohort_type    = cohort_type,
    cohort_value   = cohort_value,
    rank_by_metric = rank_by_metric,
    window_days    = if (is.na(window_days)) bigrquery::bq_param_scalar(NA, type = "INTEGER") else as.integer(window_days),
    search_query   = search_query %||% ""
  )

  run_leaderboard_query(sql_path = NULL, params = params, raw_sql = template)
}

# ---- Growth benchmarks ----

# Fetch all benchmark data for the ETL cache (all channels, all cohorts)
get_benchmark_cache <- function() {
  run_leaderboard_query(here("sql", "04_apps", "get_benchmark_cache.sql"))
}

# Fetch a single channel's benchmark data for the selected cohort
get_channel_benchmark <- function(channel_id, cohort_type, cohort_value) {
  template <- readLines(here("sql", "04_apps", "get_channel_benchmark.sql"), warn = FALSE)
  template <- glue(
    paste(template, collapse = "\n"),
    project = project,
    dataset = dataset,
    .open = "{{", .close = "}}"
  )

  params <- list(
    channel_id   = channel_id,
    cohort_type  = cohort_type,
    cohort_value = cohort_value
  )

  run_leaderboard_query(sql_path = NULL, params = params, raw_sql = template)
}
