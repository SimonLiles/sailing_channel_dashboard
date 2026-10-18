library(testthat)
library(here)

# U3 Terraform deletion-guard contract (Iteration 1B, Unit U3).
# RED baseline: every block fails until the writer delivers
# terraform/deletion_guards.md (docs-only acceptance checklist, applied at the
# future live-import session) + a pointer section in terraform/README.md.
# terraform/ is SCAFFOLD-ONLY (import blocks, zero resource bodies); guards are
# specified NOW as docs, applied THEN by the user at import. No live import,
# plan, or apply runs from this machine. All assertions are STATIC (no creds):
# file existence + content matches + git-diff guard. fail() guards keep the
# red baseline crisp: hard failure per missing deliverable, no skips.

GUARDS_DOC <- here("terraform", "deletion_guards.md")
TF_README <- here("terraform", "README.md")

read_guards_doc <- function() {
  paste(readLines(GUARDS_DOC, warn = FALSE), collapse = "\n")
}

test_that("terraform/deletion_guards.md exists (docs-only, no .tf bodies yet)", {
  if (!file.exists(GUARDS_DOC)) {
    fail(paste(
      "RED U3: terraform/deletion_guards.md missing.",
      "Writer must create the docs-only deletion-guard checklist (applied at import)."
    ))
  }
  expect_true(TRUE)
})

test_that("checklist requires lifecycle prevent_destroy on both datasets", {
  if (!file.exists(GUARDS_DOC)) {
    fail("RED U3: terraform/deletion_guards.md missing, cannot assert prevent_destroy.")
  } else {
    cfg <- read_guards_doc()
    expect_match(cfg, "prevent_destroy", fixed = TRUE,
      info = "RED U3: checklist must require lifecycle { prevent_destroy = true }.")
  }
})

test_that("checklist requires delete_contents_on_destroy = false on both datasets", {
  if (!file.exists(GUARDS_DOC)) {
    fail("RED U3: terraform/deletion_guards.md missing, cannot assert delete_contents_on_destroy.")
  } else {
    cfg <- read_guards_doc()
    expect_match(cfg, "delete_contents_on_destroy", fixed = TRUE,
      info = "RED U3: checklist must require explicit delete_contents_on_destroy = false.")
    expect_match(cfg, "false", fixed = TRUE,
      info = "RED U3: delete_contents_on_destroy must be false (never true).")
  }
})

test_that("checklist keeps table deletion_protection = true", {
  if (!file.exists(GUARDS_DOC)) {
    fail("RED U3: terraform/deletion_guards.md missing, cannot assert deletion_protection.")
  } else {
    cfg <- read_guards_doc()
    expect_match(cfg, "deletion_protection", fixed = TRUE,
      info = "RED U3: checklist must keep table deletion_protection = true.")
  }
})

test_that("checklist names both dataset resource addresses from main.tf imports", {
  if (!file.exists(GUARDS_DOC)) {
    fail("RED U3: terraform/deletion_guards.md missing, cannot assert dataset addresses.")
  } else {
    cfg <- read_guards_doc()
    expect_match(cfg, "google_bigquery_dataset.dev_dataset", fixed = TRUE,
      info = "RED U3: checklist must name google_bigquery_dataset.dev_dataset.")
    expect_match(cfg, "google_bigquery_dataset.prod_dataset", fixed = TRUE,
      info = "RED U3: checklist must name google_bigquery_dataset.prod_dataset.")
  }
})

test_that("checklist defines plan -destroy acceptance (zero deletions / hard-fail)", {
  if (!file.exists(GUARDS_DOC)) {
    fail("RED U3: terraform/deletion_guards.md missing, cannot assert plan -destroy acceptance.")
  } else {
    cfg <- read_guards_doc()
    expect_match(cfg, "plan -destroy", fixed = TRUE,
      info = "RED U3: checklist must define acceptance via terraform plan -destroy at import.")
    expect_match(cfg, "zero deletion|zero deletion|no deletion|0 deletion|hard-fail|hard fail",
      info = "RED U3: acceptance must state zero deletions proposed / hard-fails on the dataset.")
  }
})

test_that("checklist carries an import-session sign-off line", {
  if (!file.exists(GUARDS_DOC)) {
    fail("RED U3: terraform/deletion_guards.md missing, cannot assert sign-off line.")
  } else {
    cfg <- read_guards_doc()
    expect_match(cfg, "sign-off|signoff|sign off",
      info = "RED U3: checklist must carry a sign-off line for the import session.")
  }
})

test_that("terraform/README.md points at the deletion-guards checklist", {
  if (!file.exists(TF_README)) {
    fail("RED U3: terraform/README.md missing, cannot assert deletion_guards pointer.")
  } else if (!any(grepl("deletion_guards", readLines(TF_README, warn = FALSE), fixed = TRUE))) {
    fail("RED U3: terraform/README.md has no deletion_guards pointer. Writer must append one short section.")
  } else {
    expect_true(TRUE)
  }
})

test_that("no .tf files added or modified for this unit (guards are docs-only)", {
  out <- suppressWarnings(system("git diff --name-only HEAD -- 'terraform/*.tf'", intern = TRUE))
  if (length(out) > 0L && any(nzchar(trimws(out)))) {
    fail(paste(
      "RED U3: terraform/*.tf must be untouched (guards are docs-only until import).",
      "Unexpected diff:", paste(trimws(out[nzchar(trimws(out))]), collapse = ", ")
    ))
  }
  expect_true(TRUE)
})
