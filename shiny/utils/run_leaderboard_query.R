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

# Get the filtered leaderboard slice for the report builder.
# The SQL templates use --METRIC_NAMES-- and --WINDOW_CLAUSE-- as
# placeholders, substituted here based on the window selection.
get_leaderboard_slice <- function(cohort_type, cohort_value, metric_names, window_days) {
  template <- readLines(here("sql", "04_apps", "get_leaderboard_slice.sql"), warn = FALSE)
  template <- glue(
    paste(template, collapse = "\n"),
    project = project,
    dataset = dataset,
    .open = "{{", .close = "}}"
  )
  metrics_quoted <- paste(shQuote(unique(metric_names), type = "sh"), collapse = ", ")
  sql <- gsub("--METRIC_NAMES--", metrics_quoted, template, fixed = TRUE)

  if (is.na(window_days)) {
    sql <- gsub("--WINDOW_CLAUSE--", "window_days IS NULL", sql, fixed = TRUE)
    params <- list(
      cohort_type  = cohort_type,
      cohort_value = cohort_value
    )
  } else {
    sql <- gsub(
      "--WINDOW_CLAUSE--",
      "window_days = @window_days OR window_days IS NULL",
      sql, fixed = TRUE
    )
    params <- list(
      cohort_type  = cohort_type,
      cohort_value = cohort_value,
      window_days  = as.integer(window_days)
    )
  }

  run_leaderboard_query(sql_path = NULL, params = params, raw_sql = sql)
}

# Get benchmark data for the Growth Benchmarks page (all channels in a cohort).
# window_days: pass an integer for windowed metrics, or NA for lifetime.
# exclude_metric: optionally exclude one metric name (e.g. "lifetime_views_per_vid").
get_benchmark_cohort <- function(cohort_type, cohort_value, window_days, exclude_metric = NULL) {
  template <- readLines(here("sql", "04_apps", "get_benchmark_cohort.sql"), warn = FALSE)
  template <- glue(
    paste(template, collapse = "\n"),
    project = project, dataset = dataset,
    .open = "{{", .close = "}}"
  )

  params <- list(
    cohort_type  = cohort_type,
    cohort_value = cohort_value
  )

  if (is.na(window_days)) {
    template <- gsub("--WINDOW_CLAUSE--", "window_days IS NULL", template, fixed = TRUE)
  } else {
    template <- gsub("--WINDOW_CLAUSE--", "window_days = @window_days", template, fixed = TRUE)
    params$window_days <- as.integer(window_days)
  }

  if (is.null(exclude_metric)) {
    template <- gsub(
      "\n\\s*AND \\(@exclude_metric IS NULL OR metric_name != @exclude_metric\\)",
      "", template
    )
  } else {
    params$exclude_metric <- exclude_metric
  }

  run_leaderboard_query(sql_path = NULL, params = params, raw_sql = template)
}
