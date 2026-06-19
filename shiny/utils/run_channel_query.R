run_channel_query <- function(sql_path, params = NULL) {
  con <- dbConnect(
    bigrquery::bigquery(),
    project = project,
    dataset = dataset,
    billing = project
  )
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, render_sql(sql_path, project = project, dataset = dataset), params = params)
}
