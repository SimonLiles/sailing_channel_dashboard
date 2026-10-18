library(testthat)
library(here)

# U5 Restore runbook + dev rehearsal contract tests (Iteration 1B, Unit U5).
# RED baseline: every block fails until the writer delivers docs/restore-runbook.md
# covering (a) <7d time-travel, (b) >7d parquet-reload, (c) clone-rollback,
# plus exit criteria, appendix placeholders, and DEV-only rehearsal guard.
# All assertions are STATIC (no live BQ/GCS, no creds): file content matches only.
# fail() guards keep the red baseline crisp: hard failure per missing deliverable.

RUNBOOK <- here("docs", "restore-runbook.md")

read_runbook <- function() {
  paste(readLines(RUNBOOK, warn = FALSE), collapse = "\n")
}

test_that("docs/restore-runbook.md exists", {
  if (!file.exists(RUNBOOK)) {
    fail(paste(
      "RED U5: docs/restore-runbook.md missing.",
      "Writer must create it (<7d time-travel, >7d parquet-reload, clone-rollback)."
    ))
  }
  expect_true(TRUE)
})

test_that("runbook names all three restore paths", {
  if (!file.exists(RUNBOOK)) {
    fail("RED U5: docs/restore-runbook.md missing, cannot assert three restore paths.")
  } else {
    cfg <- read_runbook()
    expect_match(cfg, "(?i)time travel|time-travel|for system_time",
      perl = TRUE,
      info = "RED U5: runbook must document the <7d time-travel path.")
    expect_match(cfg, "bq load|LOAD DATA",
      info = "RED U5: runbook must document the >7d parquet-reload (bq load / LOAD DATA).")
    expect_match(cfg, "backups/",
      fixed = TRUE,
      info = "RED U5: parquet-reload path must reference the backups/ prefix.")
    expect_match(cfg, "(?i)pre_migration|pre-migration|clone",
      perl = TRUE,
      info = "RED U5: runbook must document clone-rollback (pre_migration dataset).")
  }
})

test_that("runbook names both source tables plus backfill_marts", {
  if (!file.exists(RUNBOOK)) {
    fail("RED U5: docs/restore-runbook.md missing, cannot assert table coverage.")
  } else {
    cfg <- read_runbook()
    expect_match(cfg, "channel_dimensions",
      fixed = TRUE,
      info = "RED U5: runbook must name channel_dimensions.")
    expect_match(cfg, "daily_metrics_history",
      fixed = TRUE,
      info = "RED U5: runbook must name daily_metrics_history.")
    expect_match(cfg, "backfill_marts",
      fixed = TRUE,
      info = "RED U5: runbook must reference scripts/backfill_marts.R.")
  }
})

test_that("runbook states rehearsal exit criteria with row-count check", {
  if (!file.exists(RUNBOOK)) {
    fail("RED U5: docs/restore-runbook.md missing, cannot assert exit criteria.")
  } else {
    cfg <- read_runbook()
    expect_match(cfg, "(?i)exit criteria|acceptance",
      perl = TRUE,
      info = "RED U5: runbook must state rehearsal exit/acceptance criteria.")
    expect_match(cfg, "(?i)row-count|row count",
      perl = TRUE,
      info = "RED U5: exit criteria must include a dev-vs-prod row-count comparison.")
  }
})

test_that("runbook carries literal appendix placeholders for evidence", {
  if (!file.exists(RUNBOOK)) {
    fail("RED U5: docs/restore-runbook.md missing, cannot assert appendix placeholders.")
  } else {
    cfg <- read_runbook()
    expect_match(cfg, "REHEARSAL-RESULTS",
      fixed = TRUE,
      info = "RED U5: appendix must contain literal REHEARSAL-RESULTS placeholder.")
    expect_match(cfg, "LIFECYCLE-APPLIED",
      fixed = TRUE,
      info = "RED U5: appendix must contain literal LIFECYCLE-APPLIED placeholder.")
    expect_match(cfg, "DENY-APPLIED",
      fixed = TRUE,
      info = "RED U5: appendix must contain literal DENY-APPLIED placeholder.")
  }
})

test_that("rehearsal targets DEV only with an explicit guard phrase", {
  if (!file.exists(RUNBOOK)) {
    fail("RED U5: docs/restore-runbook.md missing, cannot assert DEV-only rehearsal.")
  } else {
    cfg <- read_runbook()
    expect_match(cfg, "yt_sailing_data_dev",
      fixed = TRUE,
      info = "RED U5: rehearsal must target yt_sailing_data_dev.")
    expect_match(cfg, "(?i)dev.only|never.*prod.*rehearsal",
      perl = TRUE,
      info = "RED U5: runbook must carry a DEV-only guard phrase.")
  }
})
