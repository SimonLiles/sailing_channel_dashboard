library(testthat)
library(here)

# U1 Daily Parquet backup (ETL step 6) contract tests (Iteration 1B, Unit U1).
# RED baseline: every block fails until the writer delivers
# scripts/backup_source_tables.R (2 server-side EXPORT DATA PARQUET statements
# via render_sql/run_sql_file) + the step-6 hook in etl/main.R after the cache
# write, failure-isolated. All assertions are STATIC (no live BQ/GCS, no creds):
# file content matches + backup_prefix(date) helper contract via source()+call.
# fail() guards keep the red baseline crisp: hard failure per missing
# deliverable, no cascading errors, no skips.

BACKUP_SCRIPT <- here("scripts", "backup_source_tables.R")
MAIN_ETL <- here("etl", "main.R")

# Contract: writer MUST define backup_prefix(backup_date) in the script, where
# backup_date is a Date (default = current UTC date). It returns the shared GCS
# prefix "backups/YYYY-MM-DD" used for BOTH tables. Sourcing the script MUST be
# side-effect free (executable EXPORT/run_sql_file calls guarded so they do not
# run on source(); e.g. wrapped in a function or sys.nframe()/interactive guard).
read_backup_script <- function() {
  paste(readLines(BACKUP_SCRIPT, warn = FALSE), collapse = "\n")
}

strip_r_comments <- function(text) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  stripped <- vapply(lines, function(line) {
    sub("#.*$", "", line)
  }, character(1L))
  paste(stripped, collapse = "\n")
}

test_that("scripts/backup_source_tables.R exists", {
  if (!file.exists(BACKUP_SCRIPT)) {
    fail(paste(
      "RED U1: scripts/backup_source_tables.R missing.",
      "Writer must create it (2 EXPORT DATA PARQUET statements via render_sql/run_sql_file)."
    ))
  }
  expect_true(TRUE)
})

test_that("backup script renders + executes 2 EXPORT DATA PARQUET statements", {
  if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U1: scripts/backup_source_tables.R missing, cannot assert EXPORT DATA block.")
  } else {
    cfg <- read_backup_script()
    expect_match(cfg, "EXPORT DATA", info = "RED U1: script must contain EXPORT DATA statements.")
    expect_match(cfg, "PARQUET", info = "RED U1: EXPORT DATA must request format='PARQUET'.")
    expect_match(cfg, "render_sql", info = "RED U1: script must substitute via render_sql.")
    expect_match(cfg, "run_sql_file|run_sql", info = "RED U1: script must execute via run_sql_file/run_sql.")
    expect_match(cfg, "channel_dimensions", fixed = TRUE, info = "RED U1: script must export channel_dimensions.")
    expect_match(cfg, "daily_metrics_history", fixed = TRUE, info = "RED U1: script must export daily_metrics_history.")
    expect_match(cfg, "backups/", fixed = TRUE, info = "RED U1: backup URIs must use the backups/ prefix.")
  }
})

test_that("backup_prefix(date) yields shared UTC YYYY-MM-DD prefix for both tables", {
  if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U1: scripts/backup_source_tables.R missing, cannot assert backup_prefix(date) contract.")
  } else if (!any(grepl("backup_prefix\\s*<-\\s*function|backup_prefix\\s*=\\s*function",
    readLines(BACKUP_SCRIPT, warn = FALSE)))) {
    fail("RED U1: backup_prefix() helper missing. Writer must define backup_prefix(backup_date).")
  } else {
    env <- new.env()
    source(BACKUP_SCRIPT, local = env)
    if (!exists("backup_prefix", envir = env, mode = "function")) {
      fail("RED U1: backup_prefix() not defined as a function after source().")
    } else {
      known <- env$backup_prefix(as.Date("2026-03-05"))
      expect_equal(known, "backups/2026-03-05", info = "RED U1: backup_prefix(2026-03-05) must be backups/2026-03-05.")
      utc_now <- format(Sys.time(), tz = "UTC")
      utc_today <- format(as.Date(utc_now, tz = "UTC"), "%Y-%m-%d")
      defaulted <- env$backup_prefix()
      expect_match(defaulted, "^backups/[0-9]{4}-[0-9]{2}-[0-9]{2}$",
        info = "RED U1: default backup_prefix() must be backups/YYYY-MM-DD in UTC.")
      expect_equal(defaulted, paste0("backups/", utc_today),
        info = "RED U1: default backup_prefix() must use the current UTC date.")
      cfg <- read_backup_script()
      both_use_helper <- grepl("backup_prefix", cfg, fixed = TRUE)
      expect_true(both_use_helper, info = "RED U1: both table EXPORTs must share one backup_prefix(date).")
      expect_match(cfg, "\\*.parquet", info = "RED U1: URIs must end in /*.parquet per table.")
      expect_match(cfg, "gs://", info = "RED U1: URIs must be gs://<bucket>/backups/<date>/<table>/*.parquet.")
    }
  }
})

test_that("etl/main.R calls the backup step AFTER the GCS cache write", {
  if (!file.exists(MAIN_ETL)) {
    fail("RED U1: etl/main.R missing, cannot assert step-6 hook placement.")
  } else if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U1: scripts/backup_source_tables.R missing, step-6 hook cannot exist yet.")
  } else {
    lines <- readLines(MAIN_ETL, warn = FALSE)
    cfg <- paste(lines, collapse = "\n")
    if (!grepl("backup_source_tables", cfg, fixed = TRUE)) {
      fail("RED U1: etl/main.R never sources/calls scripts/backup_source_tables.R (step 6 missing).")
    } else {
      cache_idx <- grep("GCS cache write complete|gcs_cache_prefix|upload_as_rds", cfg)
      hook_idx <- grep("backup_source_tables", lines, fixed = TRUE)
      expect_true(length(hook_idx) >= 1L, info = "RED U1: step-6 hook must reference backup_source_tables.R.")
      expect_true(max(hook_idx) > min(cache_idx),
        info = "RED U1: backup step 6 must run AFTER the GCS cache write (consistent post-mart state).")
      expect_match(cfg, "Step 6|step 6|step-6|# 6\\.",
        info = "RED U1: backup hook must be labelled as step 6 in etl/main.R.")
    }
  }
})

test_that("etl/main.R wraps the backup step failure-isolated (never stops the job)", {
  if (!file.exists(MAIN_ETL)) {
    fail("RED U1: etl/main.R missing, cannot assert failure isolation.")
  } else if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U1: scripts/backup_source_tables.R missing, step-6 hook cannot exist yet.")
  } else {
    lines <- readLines(MAIN_ETL, warn = FALSE)
    hook_idx <- grep("backup_source_tables", lines, fixed = TRUE)
    if (length(hook_idx) == 0L) {
      fail("RED U1: etl/main.R has no backup hook to wrap failure-isolated.")
    } else {
      window <- seq(max(1L, min(hook_idx) - 6L), min(length(lines), max(hook_idx) + 6L))
      window_text <- paste(lines[window], collapse = "\n")
      expect_match(window_text, "tryCatch|withCallingHandlers|safely|try\\(",
        info = "RED U1: step-6 hook must be failure-isolated (tryCatch/withCallingHandlers/safely/try).")
      expect_match(window_text, "message|warning|log",
        info = "RED U1: isolated backup failure must log (message/warning), never stop the job.")
    }
  }
})

test_that("backup URIs never collide with the Shiny cache-* prefixes", {
  if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U1: scripts/backup_source_tables.R missing, cannot assert prefix isolation.")
  } else {
    cfg <- read_backup_script()
    expect_match(cfg, "backups/", fixed = TRUE, info = "RED U1: backup URIs must contain backups/.")
    uri_lines <- grep("gs://", strsplit(cfg, "\n", fixed = TRUE)[[1L]], value = TRUE)
    if (length(uri_lines) == 0L) {
      fail("RED U1: no gs:// backup URIs found in the script.")
    } else {
      expect_false(any(grepl("cache-dev|cache/", uri_lines)),
        info = "RED U1: backup URIs must not contain Shiny cache-dev/ or cache/ prefixes.")
    }
  }
})

test_that("backup script issues no BQ WRITE statements (EXPORT DATA only)", {
  if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U1: scripts/backup_source_tables.R missing, cannot assert read-only EXPORT.")
  } else {
    code_only <- strip_r_comments(read_backup_script())
    for (kw in c("CREATE", "MERGE", "DELETE", "DROP", "INSERT", "UPDATE")) {
      expect_false(grepl(paste0("\\b", kw, "\\b"), code_only),
        info = paste("RED U1: script must not contain BQ WRITE keyword", kw, "(EXPORT DATA only)."))
    }
    expect_match(code_only, "EXPORT DATA", info = "RED U1: script must contain EXPORT DATA (the only allowed verb).")
  }
})
