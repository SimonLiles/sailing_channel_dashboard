library(testthat)
library(here)
library(RSQLite)
library(DBI)

# U3 Liquibase OSS + SQL tests (Iteration 1, Unit U3).
# RED baseline: every block except the final regression guard fails until the
# writer delivers (a) a db/changelog/ baseline changelog (Liquibase OSS,
# BigQuery-compatible), (b) sandbox-portable SQL tests under sql/05_tests/,
# and (c) a `liquibase update` step in deploy.yml scoped to the DEV dataset.
# All assertions run WITHOUT credentials and WITHOUT a live database or a
# live `liquibase update`: only file-contract checks plus RSQLite sandbox
# execution. The live `liquibase update` runs in CI/on dev (the migrate job
# runs on main with WIF creds), never from this machine.
# Paths use here::here() per project conventions. fail() guards keep the red
# baseline crisp: one hard failure per missing deliverable, no cascading
# errors, no skips.
#
# Changelog location decision (the U3 plan left `changelog*/` vs `db/` open):
# neither `db/` nor `changelog*/` exists in this repo, so the contract below
# standardises on `db/changelog/` (Liquibase conventional layout) with a
# single master/root changelog including the per-layer changeSets.

CHANGELOG_DIR <- here("db", "changelog")

find_changelog_master <- function() {
  if (!dir.exists(CHANGELOG_DIR)) {
    return(NULL)
  }
  candidates <- list.files(
    CHANGELOG_DIR,
    pattern = "(master|root|changelog)\\.(xml|ya?ml|sql)$",
    ignore.case = TRUE,
    full.names = TRUE
  )
  if (length(candidates) == 0L) {
    return(NULL)
  }
  candidates[[1L]]
}

read_text <- function(path) {
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

test_that("baseline changelog master exists under db/changelog/", {
  master <- find_changelog_master()
  if (is.null(master)) {
    fail(paste(
      "RED U3: no Liquibase master changelog under db/changelog/.",
      "Writer must create db/changelog/ with a master/root changelog",
      "(XML, YAML, or formatted SQL) including the per-layer changeSets."
    ))
  }
  expect_true(TRUE)
})

test_that("changelog is valid Liquibase format with changeSets", {
  master <- find_changelog_master()
  if (is.null(master)) {
    fail("RED U3: no changelog master found, cannot validate Liquibase format.")
  } else {
    text <- read_text(master)
    if (grepl("\\.sql$", master, ignore.case = TRUE)) {
      expect_match(
        text, "--liquibase formatted sql", ignore.case = TRUE,
        info = "RED U3: formatted-SQL changelog must start with '--liquibase formatted sql'."
      )
      expect_match(
        text, "--changeset ", fixed = TRUE,
        info = "RED U3: formatted-SQL changelog must declare at least one --changeset."
      )
    } else {
      expect_match(
        text, "databaseChangeLog",
        info = "RED U3: XML/YAML changelog must contain a databaseChangeLog root."
      )
      expect_match(
        text, "changeSet",
        info = "RED U3: changelog must declare at least one changeSet."
      )
    }
  }
})

test_that("changelog reproduces schema intent with DATABASECHANGELOG tracking", {
  master <- find_changelog_master()
  if (is.null(master)) {
    fail("RED U3: no changelog master found, cannot assert schema tracking.")
  } else {
    text <- read_text(master)
    expect_match(
      text, "DATABASECHANGELOG",
      info = paste(
        "RED U3: changelog must reference the DATABASECHANGELOG tracking",
        "mechanism (a header comment documenting the tracking table is enough;",
        "Liquibase itself maintains the table on update)."
      )
    )
    known_tables <- c(
      "channel_dimensions",
      "mart_channel_cohorts",
      "mart_channel_metrics",
      "fct_daily_performance"
    )
    hits <- known_tables[vapply(
      known_tables,
      function(t) grepl(t, text, fixed = TRUE),
      logical(1L)
    )]
    expect_true(
      length(hits) >= 3L,
      info = paste(
        "RED U3: changelog must reproduce current schema intent: expected at",
        "least 3 of",
        paste(known_tables, collapse = ", "),
        "from sql/01_raw and sql/03_marts. Found:",
        paste(hits, collapse = ", ")
      )
    )
  }
})

test_that("changelog carries a rollback path for at least one changeSet", {
  master <- find_changelog_master()
  if (is.null(master)) {
    fail("RED U3: no changelog master found, cannot assert rollback coverage.")
  } else {
    text <- read_text(master)
    expect_match(
      text, "rollback", ignore.case = TRUE,
      info = paste(
        "RED U3: changelog has no rollback coverage. Writer must add a",
        "<rollback>/rollback block (or auto-rollback-safe change) for at",
        "least one changeSet."
      )
    )
  }
})

test_that("changelog keeps idempotent full-refresh mart rebuild semantics", {
  master <- find_changelog_master()
  if (is.null(master)) {
    fail("RED U3: no changelog master found, cannot assert mart semantics.")
  } else {
    text <- read_text(master)
    expect_match(
      text, "mart_channel_",
      info = "RED U3: changelog must version the mart tables (mart_channel_*)."
    )
    expect_match(
      text, "OR REPLACE|IF NOT EXISTS|MERGE",
      info = paste(
        "RED U3: mart changeSets must stay idempotent full-refresh compatible",
        "(CREATE OR REPLACE / IF NOT EXISTS / MERGE) so the R runner keeps",
        "its untouched rebuild semantics."
      )
    )
  }
})

run_sandbox_sql_file <- function(con, path) {
  lines <- readLines(path, warn = FALSE)
  text <- paste(lines, collapse = "\n")
  code_lines <- lines[!grepl("^\\s*--", lines)]
  code <- paste(code_lines, collapse = "\n")
  stmts <- strsplit(code, ";", fixed = TRUE)[[1L]]
  stmts <- trimws(stmts)
  stmts <- stmts[nzchar(stmts)]
  last_select <- NULL
  for (s in stmts) {
    if (grepl("^(SELECT|WITH)\\b", s, ignore.case = TRUE)) {
      last_select <- DBI::dbGetQuery(con, s)
    } else {
      DBI::dbExecute(con, s)
    }
  }
  list(n_statements = length(stmts), last_select = last_select, text = text)
}

expect_rows_annotation <- function(text) {
  m <- regmatches(
    text,
    regexpr("expect-rows\\s*:\\s*[0-9]+", text, ignore.case = TRUE)
  )
  if (length(m) == 0L) {
    return(NULL)
  }
  as.integer(regmatches(m, regexpr("[0-9]+$", m)))
}

test_that("sql/05_tests/ sandbox mart tests pass on RSQLite fixture data", {
  test_dir <- here("sql", "05_tests")
  sql_files <- if (dir.exists(test_dir)) {
    list.files(test_dir, pattern = "\\.sql$", recursive = TRUE, full.names = TRUE)
  } else {
    character(0)
  }
  if (length(sql_files) == 0L) {
    fail(paste(
      "RED U3: sql/05_tests/ has no .sql test files. Writer must populate",
      "sql/05_tests/ with sandbox-portable (SQLite-runnable) fixture +",
      "query files. NOTE: the real mart files (e.g. 03_marts MERGE with",
      "{{project}}.{{dataset}} placeholders) are BigQuery-dialect by design",
      "and must NOT run here; port the mart logic under test to SQLite."
    ))
  } else {
    blobs <- vapply(sql_files, read_text, character(1L))
    has_mart <- any(grepl("cohort|ranking|mart_|metric", blobs, ignore.case = TRUE))
    has_annotation <- any(vapply(
      blobs, function(b) !is.null(expect_rows_annotation(b)), logical(1L)
    ))
    if (!has_mart) {
      fail(paste(
        "RED U3: no sql/05_tests/ file exercises mart logic. At least one",
        "test file must cover a mart concept (cohort, ranking, mart_*, metric)."
      ))
    } else if (!has_annotation) {
      fail(paste(
        "RED U3: no sql/05_tests/ file carries a query-result assertion.",
        "At least one test file must end with a SELECT annotated with",
        "'-- expect-rows: N' stating the exact expected row count."
      ))
    } else {
      for (i in seq_along(sql_files)) {
        f <- sql_files[[i]]
        con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
        res <- tryCatch(run_sandbox_sql_file(con, f), error = function(e) e)
        DBI::dbDisconnect(con)
        if (inherits(res, "error")) {
          fail(paste0(
            "RED U3: sandbox execution failed for ", f, ": ",
            conditionMessage(res),
            ". Test files must be self-contained (fixtures + query in one",
            " file) and SQLite-runnable with ';'-separated statements."
          ))
        } else {
          n <- expect_rows_annotation(blobs[[i]])
          if (!is.null(n)) {
            if (is.null(res$last_select)) {
              fail(paste0(
                "RED U3: annotated file ", f,
                " has no final SELECT to assert '-- expect-rows: ", n, "' against."
              ))
            } else {
              expect_equal(
                nrow(res$last_select), n,
                info = paste0(
                  "RED U3: ", f, " expected ", n,
                  " rows, got ", nrow(res$last_select), "."
                )
              )
            }
          }
        }
      }
    }
  }
})

test_that("CI wires a liquibase update step scoped to the dev dataset", {
  workflow_path <- here(".github", "workflows", "deploy.yml")
  if (!file.exists(workflow_path)) {
    fail("RED U3: .github/workflows/deploy.yml missing, cannot assert Liquibase CI step.")
  }
  workflow_lines <- readLines(workflow_path, warn = FALSE)
  workflow <- paste(workflow_lines, collapse = "\n")
  if (!grepl("liquibase", workflow, ignore.case = TRUE)) {
    fail(paste(
      "RED U3: deploy.yml has no liquibase step. Writer must add a",
      "`liquibase update` step scoped to the DEV dataset",
      "(yt_sailing_data_dev), running with WIF creds like the migrate job;",
      "prod `liquibase update` from this machine is out of scope."
    ))
  } else {
    liq_idx <- grep("liquibase", workflow_lines, ignore.case = TRUE)
    window <- unique(unlist(lapply(
      liq_idx,
      function(i) seq(max(1L, i - 6L), min(length(workflow_lines), i + 6L))
    )))
    window_text <- paste(workflow_lines[window], collapse = "\n")
    expect_match(
      window_text, "yt_sailing_data_dev|\\bdev\\b", ignore.case = TRUE,
      info = paste(
        "RED U3: the liquibase CI step must be scoped to the dev dataset",
        "(expect yt_sailing_data_dev or dev/DATASET wiring within 6 lines of",
        "the liquibase step); the prod migrate job stays Liquibase-free."
      )
    )
  }
})

test_that("U3 regression: R mart-rebuild runner untouched by Liquibase", {
  if (!file.exists(here("scripts", "backfill_marts.R"))) {
    fail("RED U3: scripts/backfill_marts.R missing (R runner must keep idempotent rebuilds).")
  }
  if (!file.exists(here("scripts", "migrate_schema.R"))) {
    fail("RED U3: scripts/migrate_schema.R missing (writer must not remove migrate scripts).")
  }
  r_files <- unlist(lapply(c("scripts", "etl", "shiny"), function(d) {
    p <- here(d)
    if (!dir.exists(p)) {
      return(character(0))
    }
    list.files(p, pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
  }))
  hits <- r_files[vapply(
    r_files,
    function(f) any(grepl("liquibase", readLines(f, warn = FALSE), ignore.case = TRUE)),
    logical(1L)
  )]
  expect_equal(
    length(hits), 0L,
    info = paste(
      c(
        "RED U3: R runner must stay Liquibase-free (Liquibase lives in db/changelog/ + CI only).",
        hits
      ),
      collapse = "\n"
    )
  )
})
