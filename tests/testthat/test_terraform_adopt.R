library(testthat)
library(here)

# U2 terraform full-adopt (scaffold-only) contract tests (Iteration 1, Unit U2).
# RED baseline: every block fails until the writer delivers terraform/
# scaffolding (versions/backend/variables/main with import blocks), documents
# the import-then-verify procedure, and wires fmt/validate into deploy.yml.
# All assertions run WITHOUT credentials and WITHOUT live import/plan/apply:
# only `fmt -check` and `init -backend=false` + `validate` (provider download
# only, no auth) are exercised. Paths use here::here() per project conventions.
# fail() guards keep the red baseline crisp: one hard failure per missing
# deliverable, no cascading errors, no skips.

tf_binary <- Sys.which("terraform")

test_that("terraform/ scaffold files exist (versions/backend/variables/main)", {
  tf_files <- c("versions.tf", "backend.tf", "variables.tf", "main.tf")
  missing <- tf_files[!file.exists(file.path(here("terraform"), tf_files))]
  if (length(missing) > 0L) {
    fail(paste(
      "RED U2: terraform/ scaffold missing:",
      paste(missing, collapse = ", "),
      ". Writer must create terraform/versions.tf, backend.tf, variables.tf, main.tf."
    ))
  }
  expect_true(TRUE)
})

test_that("versions.tf pins terraform and hashicorp/google provider", {
  versions_path <- here("terraform", "versions.tf")
  if (!file.exists(versions_path)) {
    fail("RED U2: terraform/versions.tf missing, cannot pin versions.")
  } else {
    cfg <- paste(readLines(versions_path, warn = FALSE), collapse = "\n")
    expect_match(cfg, "required_version", info = "RED U2: versions.tf must declare required_version.")
    expect_match(cfg, "hashicorp/google", info = "RED U2: versions.tf must pin the hashicorp/google provider.")
    expect_match(cfg, "~> |=", info = "RED U2: versions.tf must pin versions (~> or =).")
  }
})

test_that("backend.tf declares GCS backend with exact bucket and prefix", {
  backend_path <- here("terraform", "backend.tf")
  if (!file.exists(backend_path)) {
    fail("RED U2: terraform/backend.tf missing, cannot declare GCS backend.")
  } else {
    cfg <- paste(readLines(backend_path, warn = FALSE), collapse = "\n")
    expect_match(cfg, 'backend\\s+"gcs"', info = "RED U2: backend.tf must declare backend \"gcs\".")
    expect_match(cfg, "yt-sailing-dashboard-tf-state", fixed = TRUE, info = "RED U2: backend.tf must use bucket yt-sailing-dashboard-tf-state.")
    expect_match(cfg, "terraform/state", fixed = TRUE, info = "RED U2: backend.tf must use prefix terraform/state.")
  }
})

test_that("variables.tf declares project/region defaults", {
  variables_path <- here("terraform", "variables.tf")
  if (!file.exists(variables_path)) {
    fail("RED U2: terraform/variables.tf missing, cannot declare variables.")
  } else {
    cfg <- paste(readLines(variables_path, warn = FALSE), collapse = "\n")
    expect_match(cfg, "project", info = "RED U2: variables.tf must declare a project variable.")
    expect_match(cfg, "yt-sailing-dashboard", fixed = TRUE, info = "RED U2: project default must be yt-sailing-dashboard.")
    expect_match(cfg, "region", info = "RED U2: variables.tf must declare a region variable.")
    expect_match(cfg, "us-central1", fixed = TRUE, info = "RED U2: region default must be us-central1.")
  }
})

test_that("main.tf uses import blocks data-layer-first (BQ/IAM first, Cloud Run last)", {
  main_path <- here("terraform", "main.tf")
  if (!file.exists(main_path)) {
    fail("RED U2: terraform/main.tf missing, cannot assert import-block order.")
  } else {
    cfg_lines <- readLines(main_path, warn = FALSE)
    cfg <- paste(cfg_lines, collapse = "\n")
    n_imports <- length(gregexpr("(?m)^\\s*import\\s*\\{", cfg, perl = TRUE)[[1]])
    if (n_imports < 1L || (length(n_imports) == 1L && n_imports < 0L)) {
      fail("RED U2: main.tf has no import blocks. Writer must scaffold data-layer-first import blocks, not handwritten resource bodies.")
    } else {
      # Collect `to = ...` targets in file order; first must be data layer
      # (BigQuery dataset/IAM), last must be serving (Cloud Run).
      to_lines <- grep("^\\s*to\\s*=", cfg_lines, value = TRUE)
      if (length(to_lines) < 1L) {
        fail("RED U2: main.tf import blocks have no `to =` targets.")
      } else {
        first_to <- to_lines[1L]
        last_to <- to_lines[length(to_lines)]
        expect_match(
          first_to, "bigquery|bq_|_iam|iam_",
          info = "RED U2: first import block must target a BigQuery dataset/IAM resource (data layer first)."
        )
        expect_match(
          last_to, "cloud_run|cloudrun|_run\\.|run_",
          info = "RED U2: last import block must target a Cloud Run resource (serving last)."
        )
      }
      expect_match(
        cfg, "[Bb]atch",
        info = "RED U2: each import block must be commented with its batch (datasets/IAM -> storage/registry -> scheduling -> serving)."
      )
    }
  }
})

test_that("terraform fmt -check exits 0 (no creds, local only)", {
  if (!nzchar(tf_binary)) {
    skip("terraform binary not on PATH")
  } else if (!dir.exists(here("terraform"))) {
    fail("RED U2: terraform/ missing, nothing for `fmt -check`.")
  } else {
    out <- system2(tf_binary, c("fmt", "-check", "-recursive", shQuote(here("terraform"))), stdout = TRUE, stderr = TRUE)
    out_status <- attr(out, "status", exact = TRUE)
    if (is.null(out_status)) out_status <- 0L
    expect_equal(
      out_status, 0L,
      info = paste(c("RED U2: `terraform fmt -check` is not green.", out), collapse = "\n")
    )
  }
})

test_that("terraform init -backend=false + validate exit 0 (no auth)", {
  if (!nzchar(tf_binary)) {
    skip("terraform binary not on PATH")
  } else if (!dir.exists(here("terraform"))) {
    fail("RED U2: terraform/ missing, nothing to init/validate.")
  } else {
    init_out <- system2(
      tf_binary,
      c(paste0("-chdir=", shQuote(here("terraform"))), "init", "-backend=false", "-input=false"),
      stdout = TRUE, stderr = TRUE
    )
    init_status <- attr(init_out, "status", exact = TRUE)
    if (is.null(init_status)) init_status <- 0L
    expect_equal(
      init_status, 0L,
      info = paste(c("RED U2: `terraform init -backend=false` failed (must run with no auth).", init_out), collapse = "\n")
    )
    val_out <- system2(
      tf_binary,
      c(paste0("-chdir=", shQuote(here("terraform"))), "validate", "-no-color"),
      stdout = TRUE, stderr = TRUE
    )
    val_status <- attr(val_out, "status", exact = TRUE)
    if (is.null(val_status)) val_status <- 0L
    expect_equal(
      val_status, 0L,
      info = paste(c("RED U2: `terraform validate` failed (must run with no auth).", val_out), collapse = "\n")
    )
  }
})

test_that("CI deploy.yml has terraform fmt/validate steps with no secrets in those steps", {
  workflow_path <- here(".github", "workflows", "deploy.yml")
  if (!file.exists(workflow_path)) {
    fail("RED U2: .github/workflows/deploy.yml missing, cannot assert terraform CI steps.")
  } else {
    workflow_lines <- readLines(workflow_path, warn = FALSE)
    workflow <- paste(workflow_lines, collapse = "\n")
    expect_match(workflow, "terraform", info = "RED U2: deploy.yml has no terraform steps. Writer must add fmt -check + validate.")
    expect_match(workflow, "fmt", info = "RED U2: deploy.yml terraform steps must run fmt -check.")
    expect_match(workflow, "validate", info = "RED U2: deploy.yml terraform steps must run validate.")
    tf_idx <- grep("terraform", workflow_lines, ignore.case = TRUE)
    if (length(tf_idx) == 0L) {
      fail("RED U2: no terraform lines in deploy.yml to check for secrets.")
    } else {
      # Secret-needing jobs stay off this path: the terraform fmt/validate
      # steps must not reference secrets. (Check a window around each
      # terraform line to catch run: + env: lines of the same step.)
      window <- unique(unlist(lapply(tf_idx, function(i) seq(max(1L, i - 4L), min(length(workflow_lines), i + 4L)))))
      window_text <- paste(workflow_lines[window], collapse = "\n")
      expect_false(
        grepl("secrets\\.", window_text),
        info = "RED U2: terraform fmt/validate steps must use no secrets (secret-needing jobs stay off this path)."
      )
    }
  }
})

test_that("import-then-verify procedure is documented (README or header comments)", {
  readme_path <- here("terraform", "README.md")
  main_path <- here("terraform", "main.tf")
  versions_path <- here("terraform", "versions.tf")
  doc_text <- ""
  if (file.exists(readme_path)) {
    doc_text <- paste(c(doc_text, paste(readLines(readme_path, warn = FALSE), collapse = "\n")), collapse = "\n")
  }
  for (p in c(main_path, versions_path)) {
    if (file.exists(p)) {
      doc_text <- paste(c(doc_text, paste(readLines(p, warn = FALSE), collapse = "\n")), collapse = "\n")
    }
  }
  if (!nzchar(doc_text) || !grepl("import", doc_text, ignore.case = TRUE)) {
    fail("RED U2: import-then-verify procedure undocumented. Writer must add terraform/README.md or header comments (procedure + batch order + who/where live import runs).")
  } else {
    expect_match(doc_text, "[Ii]mport", info = "RED U2: docs must describe the import-then-verify procedure.")
    expect_match(doc_text, "[Bb]atch|[Oo]rder", info = "RED U2: docs must state the batch order (datasets/IAM -> storage/registry -> scheduling -> serving).")
  }
})

test_that("U1 regression: .tf scaffold does not break lintr/ruff gates", {
  # lintr::lint_dir('.') lints only R files and `ruff check` only Python, so
  # .tf files are inherently out of scope — but assert the scaffold keeps it
  # that way (no .R/.py strays under terraform/) and U1 gate files are intact.
  if (!file.exists(here("tests", "testthat", "test_lint_gates.R"))) {
    fail("RED U2: U1 gate test tests/testthat/test_lint_gates.R missing (must stay green).")
  } else if (!file.exists(here(".lintr.R"))) {
    fail("RED U2: U1 .lintr.R missing (writer must not break U1).")
  } else if (!file.exists(here("pyproject.toml"))) {
    fail("RED U2: U1 pyproject.toml missing (writer must not break U1).")
  } else if (dir.exists(here("terraform"))) {
    strays <- list.files(here("terraform"), pattern = "\\.[Rr]$|\\.py$", recursive = TRUE, full.names = FALSE)
    expect_equal(
      length(strays), 0L,
      info = paste(c("RED U2: terraform/ must contain no .R/.py files (would enter lintr/ruff scope).", strays), collapse = "\n")
    )
  } else {
    fail("RED U2: terraform/ missing, cannot assert U1 lint-scope isolation.")
  }
})
