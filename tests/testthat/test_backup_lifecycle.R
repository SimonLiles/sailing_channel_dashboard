library(testthat)
library(here)

# U2 60-day GCS lifecycle rule contract tests (Iteration 1B, Unit U2).
# RED baseline: every block fails until the writer delivers
# docs/backup-lifecycle.json (valid GCS lifecycle JSON, exactly one rule:
# prefix backups/, age 60 days, action Delete). All assertions are STATIC
# (no GCP, no creds): file exists + parses + rule shape + delete-only +
# prefix cross-check against backup_prefix() in scripts/backup_source_tables.R.
# fail() guards keep the red baseline crisp: hard failure per missing
# deliverable, no cascading errors, no skips.

LIFECYCLE_JSON <- here("docs", "backup-lifecycle.json")
BACKUP_SCRIPT <- here("scripts", "backup_source_tables.R")

# Raw lifecycle file text (single string) for text-level assertions.
read_lifecycle_text <- function() {
  paste(readLines(LIFECYCLE_JSON, warn = FALSE), collapse = "\n")
}

# Parsed lifecycle JSON as nested lists (simplify off keeps rule lists stable).
read_lifecycle_json <- function() {
  jsonlite::fromJSON(read_lifecycle_text(), simplifyVector = FALSE)
}

# Rule list regardless of top-level shape (lifecycle.rule[] or bare rule[]).
lifecycle_rules <- function(parsed) {
  if (!is.null(parsed[["lifecycle"]][["rule"]])) {
    parsed[["lifecycle"]][["rule"]]
  } else if (!is.null(parsed[["rule"]])) {
    parsed[["rule"]]
  } else {
    NULL
  }
}

# TRUE when a rule condition targets the backups/ prefix (any key spelling).
rule_targets_backups <- function(condition) {
  if (is.null(condition)) {
    return(FALSE)
  }
  candidates <- c(
    as.character(unlist(condition[["matchesPrefix"]])),
    as.character(unlist(condition[["matches_prefix"]])),
    as.character(unlist(condition[["prefix"]])),
    as.character(unlist(condition[["startsWith"]])),
    as.character(unlist(condition[["matches_prefixes"]]))
  )
  any(grepl("backups/", candidates, fixed = TRUE))
}

test_that("docs/backup-lifecycle.json exists", {
  if (!file.exists(LIFECYCLE_JSON)) {
    fail(paste(
      "RED U2: docs/backup-lifecycle.json missing.",
      "Writer must create it (one delete-only rule: backups/, age 60)."
    ))
  }
  expect_true(TRUE)
})

test_that("lifecycle file parses as JSON", {
  if (!file.exists(LIFECYCLE_JSON)) {
    fail("RED U2: docs/backup-lifecycle.json missing, cannot assert JSON parses.")
  } else if (!requireNamespace("jsonlite", quietly = TRUE)) {
    fail("RED U2: jsonlite unavailable, cannot parse docs/backup-lifecycle.json.")
  } else {
    parsed <- tryCatch(read_lifecycle_json(), error = function(e) NULL)
    if (is.null(parsed)) {
      fail("RED U2: docs/backup-lifecycle.json is not valid JSON.")
    } else {
      expect_true(TRUE)
    }
  }
})

test_that("lifecycle has exactly one rule: Delete at age 60 for backups/", {
  if (!file.exists(LIFECYCLE_JSON)) {
    fail("RED U2: docs/backup-lifecycle.json missing, cannot assert rule shape.")
  } else if (!requireNamespace("jsonlite", quietly = TRUE)) {
    fail("RED U2: jsonlite unavailable, cannot assert rule shape.")
  } else {
    parsed <- tryCatch(read_lifecycle_json(), error = function(e) NULL)
    if (is.null(parsed)) {
      fail("RED U2: docs/backup-lifecycle.json is not valid JSON.")
    } else {
      rules <- lifecycle_rules(parsed)
      if (is.null(rules) || length(rules) == 0L) {
        fail("RED U2: no lifecycle rule found (need one Delete rule for backups/ at age 60).")
      } else {
        expect_equal(length(rules), 1L, info = "RED U2: lifecycle must hold exactly one rule.")
        is_delete_60_backups <- vapply(rules, function(rule) {
          action_ok <- identical(as.character(rule[["action"]][["type"]]), "Delete")
          age_ok <- identical(as.numeric(rule[["condition"]][["age"]]), 60)
          prefix_ok <- rule_targets_backups(rule[["condition"]])
          isTRUE(action_ok) && isTRUE(age_ok) && isTRUE(prefix_ok)
        }, logical(1L))
        expect_true(any(is_delete_60_backups),
          info = "RED U2: need a rule with action Delete, condition age 60, prefix backups/.")
      }
    }
  }
})

test_that("lifecycle is delete-only (no SetStorageClass or other actions)", {
  if (!file.exists(LIFECYCLE_JSON)) {
    fail("RED U2: docs/backup-lifecycle.json missing, cannot assert delete-only.")
  } else if (!requireNamespace("jsonlite", quietly = TRUE)) {
    fail("RED U2: jsonlite unavailable, cannot assert delete-only.")
  } else {
    parsed <- tryCatch(read_lifecycle_json(), error = function(e) NULL)
    if (is.null(parsed)) {
      fail("RED U2: docs/backup-lifecycle.json is not valid JSON.")
    } else {
      rules <- lifecycle_rules(parsed)
      if (is.null(rules) || length(rules) == 0L) {
        fail("RED U2: no lifecycle rule found, cannot assert delete-only.")
      } else {
        action_types <- vapply(rules, function(rule) as.character(rule[["action"]][["type"]]), character(1L))
        expect_true(all(action_types == "Delete"),
          info = "RED U2: every rule action type must be Delete (no SetStorageClass).")
        raw <- read_lifecycle_text()
        expect_false(grepl("SetStorageClass", raw, fixed = TRUE),
          info = "RED U2: lifecycle must not mention SetStorageClass (surprise restores).")
      }
    }
  }
})

test_that("lifecycle backups/ prefix matches backup_prefix() output prefix", {
  if (!file.exists(BACKUP_SCRIPT)) {
    fail("RED U2: scripts/backup_source_tables.R missing, cannot cross-check backups/ prefix.")
  } else {
    env <- new.env()
    sourced <- tryCatch({
      source(BACKUP_SCRIPT, local = env)
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(sourced)) {
      fail("RED U2: sourcing scripts/backup_source_tables.R errored (must be side-effect free).")
    } else if (!exists("backup_prefix", envir = env, mode = "function")) {
      fail("RED U2: backup_prefix() not defined after source(), cannot cross-check prefix.")
    } else {
      known <- env$backup_prefix(as.Date("2026-03-05"))
      expect_true(startsWith(known, "backups/"),
        info = "RED U2: backup_prefix(2026-03-05) must start with backups/ to match the lifecycle rule.")
    }
  }
})
