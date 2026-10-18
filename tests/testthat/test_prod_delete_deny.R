library(testthat)
library(here)

# U4 IAM deny on prod dataset deletion contract tests (Iteration 1B, Unit U4).
# RED baseline: every block fails until the writer delivers docs/prod-delete-deny.md.
# All assertions are STATIC (no IAM, no gcloud, no creds): markdown content matches only.
# fail() guards keep the red baseline crisp: hard failure per missing deliverable,
# no cascading errors, no skips.

DENY_DOC <- here("docs", "prod-delete-deny.md")

# Helper: read the doc as one string. Callers must fail() first when the file is missing.
read_deny_doc <- function() {
  paste(readLines(DENY_DOC, warn = FALSE), collapse = "\n")
}

test_that("docs/prod-delete-deny.md exists", {
  if (!file.exists(DENY_DOC)) {
    fail(paste(
      "RED U4: docs/prod-delete-deny.md missing.",
      "Writer must create it with deny scope, principals, apply, negative-test, rollback sections."
    ))
  }
  expect_true(TRUE)
})

test_that("doc names the deny scope permission, dataset, project, and deny", {
  if (!file.exists(DENY_DOC)) {
    fail("RED U4: docs/prod-delete-deny.md missing, cannot assert deny scope.")
  } else {
    doc <- read_deny_doc()
    expect_match(doc, "bigquery.datasets.delete", fixed = TRUE,
      info = "RED U4: doc must name permission bigquery.datasets.delete.")
    expect_match(doc, "yt_sailing_data", fixed = TRUE,
      info = "RED U4: doc must name prod dataset yt_sailing_data.")
    expect_match(doc, "yt-sailing-dashboard", fixed = TRUE,
      info = "RED U4: doc must name project yt-sailing-dashboard.")
    expect_match(doc, "deny", ignore.case = TRUE,
      info = "RED U4: doc must describe the deny (any case).")
  }
})

test_that("doc reserves break-glass to the human owner", {
  if (!file.exists(DENY_DOC)) {
    fail("RED U4: docs/prod-delete-deny.md missing, cannot assert break-glass/owner reservation.")
  } else {
    doc <- read_deny_doc()
    expect_match(doc, "owner|break-glass|break glass", ignore.case = TRUE,
      info = "RED U4: doc must reserve break-glass/owner (owner|break-glass|break glass).")
  }
})

test_that("doc contains a SAFE negative-test procedure section", {
  if (!file.exists(DENY_DOC)) {
    fail("RED U4: docs/prod-delete-deny.md missing, cannot assert negative-test section.")
  } else {
    doc <- read_deny_doc()
    expect_match(doc, "negative|permission-denied|permission denied", ignore.case = TRUE,
      info = "RED U4: doc must contain a negative-test section (negative|permission-denied).")
  }
})

test_that("doc carries an explicit never-attempt-destructively warning", {
  if (!file.exists(DENY_DOC)) {
    fail("RED U4: docs/prod-delete-deny.md missing, cannot assert never-destructive warning.")
  } else {
    doc <- read_deny_doc()
    expect_match(doc, "never|do not attempt|non-destructive", ignore.case = TRUE,
      info = "RED U4: doc must warn NEVER to attempt destructively (never|do not attempt|non-destructive).")
  }
})

test_that("doc leaks no secret material", {
  if (!file.exists(DENY_DOC)) {
    fail("RED U4: docs/prod-delete-deny.md missing, cannot assert no-secret-material.")
  } else {
    doc <- read_deny_doc()
    expect_false(grepl("private_key", doc, fixed = TRUE),
      info = "RED U4: doc must not contain private_key secret material.")
    expect_false(grepl("client_email.*gserviceaccount", doc),
      info = "RED U4: doc must not contain a service-account client_email.")
    expect_false(grepl("-----BEGIN", doc, fixed = TRUE),
      info = "RED U4: doc must not contain a -----BEGIN key block.")
  }
})
