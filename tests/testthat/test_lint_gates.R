library(testthat)
library(here)

# U1 lint-gate contract tests (Iteration 1, Unit U1).
# RED baseline: every block fails until the writer delivers
# .lintr.R + pyproject.toml (ruff) + CI lint job + AGENTS.md lint commands.
# Paths use here::here() per project test conventions.
# fail() guards keep the red baseline crisp: one failure per missing
# deliverable, no cascading errors/warnings, no skips.

test_that("lintr config (.lintr.R) exists at repo root", {
  if (!file.exists(here(".lintr.R"))) {
    fail("RED U1: .lintr.R missing at repo root. Writer must create it.")
  }
  expect_true(TRUE)
})

test_that(".lintr.R declares linters", {
  lintr_path <- here(".lintr.R")
  if (!file.exists(lintr_path)) {
    fail("RED U1: .lintr.R missing, cannot declare linters.")
  } else {
    cfg <- paste(readLines(lintr_path, warn = FALSE), collapse = "\n")
    expect_match(cfg, "linters", info = "RED U1: .lintr.R must declare linters.")
  }
})

test_that("ruff config (pyproject.toml) exists with [tool.ruff] scoped to admin/", {
  pyproject_path <- here("pyproject.toml")
  if (!file.exists(pyproject_path)) {
    fail("RED U1: pyproject.toml missing. Writer must create ruff config.")
  } else {
    cfg <- paste(readLines(pyproject_path, warn = FALSE), collapse = "\n")
    expect_match(cfg, "\\[tool\\.ruff", info = "RED U1: pyproject.toml needs [tool.ruff].")
    expect_match(cfg, "admin", info = "RED U1: ruff config must scope the upcoming admin/ service.")
  }
})

test_that("ruff config validates standalone (ruff check exits 0 on clean tree)", {
  # No Python sources exist yet (admin/ is planned); the config alone must
  # let `ruff check` run green. Fails red while binary or config is absent.
  ruff_bin <- Sys.which("ruff")
  if (!file.exists(here("pyproject.toml"))) {
    fail("RED U1: pyproject.toml missing, nothing for ruff to validate.")
  } else if (!nzchar(ruff_bin)) {
    fail("RED U1: ruff binary not on PATH. Writer must document/install it (pip install ruff).")
  } else {
    out <- system2(
      ruff_bin,
      c("check", "--config", here("pyproject.toml"), "."),
      stdout = TRUE, stderr = TRUE
    )
    out_status <- attr(out, "status", exact = TRUE)
    if (is.null(out_status)) out_status <- 0L
    expect_equal(
      out_status, 0L,
      info = paste(c("RED U1: `ruff check` is not green on the clean tree.", out), collapse = "\n")
    )
  }
})

test_that("CI deploy.yml has a lint job running lintr + ruff", {
  workflow <- paste(readLines(here(".github", "workflows", "deploy.yml"), warn = FALSE), collapse = "\n")
  expect_match(workflow, "(?m)^\\s*lint\\s*:", perl = TRUE, info = "RED U1: no `lint:` job in deploy.yml.")
  expect_match(workflow, "lintr", info = "RED U1: CI lint job must run lintr.")
  expect_match(workflow, "ruff", info = "RED U1: CI lint job must run ruff.")
})

test_that("AGENTS.md Commands table documents exact lint commands", {
  agents <- paste(readLines(here("AGENTS.md"), warn = FALSE), collapse = "\n")
  expect_match(agents, "lintr::", info = "RED U1: AGENTS.md has no executable lintr command (expect e.g. lintr::lint_dir).")
  expect_match(agents, "ruff check", fixed = TRUE, info = "RED U1: AGENTS.md has no exact `ruff check` command.")
})

test_that("scratch violations flip the gates red (sensitivity demo)", {
  # Proves the gates are sensitive, not vacuous: a scratch R file with an
  # assignment-linter violation and a scratch Python file with an unused
  # import must BOTH be flagged, then removed. Fails red while lintr/ruff
  # or their configs are absent; passes green once the writer wires them.
  # NOTE: guarded requires (no bare `::` on missing packages) so absence
  # records a hard RED failure instead of a testthat auto-skip.
  if (!requireNamespace("lintr", quietly = TRUE)) {
    fail("RED U1: lintr R package not installed, cannot demo red flip.")
  } else if (!nzchar(Sys.which("ruff"))) {
    fail("RED U1: ruff binary missing, cannot demo red flip.")
  } else if (!file.exists(here("pyproject.toml"))) {
    fail("RED U1: pyproject.toml missing, cannot demo ruff red flip.")
  } else {
    scratch_r <- file.path(tempdir(), "u1_scratch_violation.R")
    writeLines("u1_scratch_flipper=1", scratch_r)
    on.exit(unlink(scratch_r, force = TRUE), add = TRUE)
    r_lints <- lintr::lint(scratch_r)
    expect_true(
      length(r_lints) > 0L,
      info = "RED U1: lintr did not flag the scratch R violation; gate is not sensitive."
    )

    scratch_py <- file.path(tempdir(), "u1_scratch_violation.py")
    writeLines("import os", scratch_py)
    on.exit(unlink(scratch_py, force = TRUE), add = TRUE)
    status <- system2(
      Sys.which("ruff"),
      c("check", "--config", here("pyproject.toml"), "--no-cache", scratch_py),
      stdout = FALSE, stderr = FALSE
    )
    expect_true(
      !is.null(status) && status != 0L,
      info = "RED U1: ruff did not flag the scratch Python violation; gate is not sensitive."
    )
    unlink(c(scratch_r, scratch_py), force = TRUE)
  }
})
