library(testthat)
library(here)

# U4 required PR checks + Trivy advisory (Iteration 1, Unit U4).
# RED baseline: every block except the final no-behavior-change regression
# guard fails until the writer adds a `pull_request` trigger, secret-free PR
# gating, Trivy fs/config + image scans (advisory, SARIF), and a
# required-checks note to .github/workflows/deploy.yml.
# All assertions are STATIC YAML/content checks — they run WITHOUT
# credentials and WITHOUT the trivy binary installed (no live scan runs;
# no Sys.which gate needed because nothing shells out to trivy).
# Paths use here::here() per project conventions. fail() guards keep the red
# baseline crisp: one hard failure per missing deliverable, no skips.

WORKFLOW_PATH <- here(".github", "workflows", "deploy.yml")

read_workflow <- function() {
  if (!file.exists(WORKFLOW_PATH)) {
    return(NULL)
  }
  lines <- readLines(WORKFLOW_PATH, warn = FALSE)
  list(lines = lines, text = paste(lines, collapse = "\n"))
}

# Split top-level job blocks: lines matching `^  <name>:` start a new job.
job_blocks <- function(lines) {
  starts <- grep("^  [A-Za-z0-9][A-Za-z0-9_-]*:", lines)
  if (length(starts) == 0L) {
    return(list())
  }
  names <- sub("^  ([A-Za-z0-9][A-Za-z0-9_-]*):.*$", "\\1", lines[starts])
  ends <- c(starts[-1L] - 1L, length(lines))
  blocks <- lapply(seq_along(starts), function(i) {
    paste(lines[seq(starts[i], ends[i])], collapse = "\n")
  })
  names(blocks) <- names
  blocks
}

PR_GATED_JOBS <- c("build-etl", "build-shiny", "migrate", "liquibase-dev", "deploy")
PR_RUN_JOBS <- c("lint", "terraform", "test")

test_that("pull_request trigger present in deploy.yml (alongside push:main)", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert PR trigger.")
  } else {
    expect_match(
      wf$text, "pull_request",
      info = "RED U4: deploy.yml has no `pull_request` trigger. Writer must add it alongside `push: main`."
    )
    expect_match(
      wf$text, "push",
      info = "RED U4: deploy.yml lost its `push` trigger (push: main must stay)."
    )
    expect_match(
      wf$text, '"main"|\\bmain\\b',
      info = "RED U4: deploy.yml must still trigger on `main`."
    )
  }
})

test_that("secret-free PR path: PR-running jobs use NO secrets/WIF auth", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert secret-free PR path.")
  } else {
    blocks <- job_blocks(wf$lines)
    present <- PR_RUN_JOBS[PR_RUN_JOBS %in% names(blocks)]
    if (length(present) == 0L) {
      fail("RED U4: no lint/terraform/test jobs found in deploy.yml to assert secret-free PR path.")
    } else {
      for (j in present) {
        expect_false(
          grepl("secrets\\.", blocks[[j]]),
          info = paste0("RED U4: PR-running job `", j, "` must contain NO `secrets.*` (PR jobs are secret-free).")
        )
        expect_false(
          grepl("google-github-actions/auth", blocks[[j]]),
          info = paste0("RED U4: PR-running job `", j, "` must NOT use WIF `google-github-actions/auth` (secret-needing auth stays off PR runs).")
        )
      }
      # Live tests self-skip without a key: the test gate must NOT pass
      # YT_API_KEY on PR (or must document self-skip).
      test_block <- if ("test" %in% names(blocks)) blocks[["test"]] else ""
      has_key_ref <- grepl("YT_API_KEY", test_block)
      has_pr_guard <- grepl("pull_request", test_block)
      has_selfskip_note <- grepl("self-skip|selfskip|skip without|without.*key", wf$text, ignore.case = TRUE)
      if (has_key_ref && !(has_pr_guard || has_selfskip_note)) {
        fail(paste(
          "RED U4: test gate references YT_API_KEY with no PR guard.",
          "Writer must NOT pass YT_API_KEY on PR, or must document live-test self-skip."
        ))
      }
      expect_true(TRUE)
    }
  }
})

test_that("creds-needing jobs gated off PR runs (build-*/migrate/liquibase-dev/deploy)", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert creds-job PR gating.")
  } else {
    blocks <- job_blocks(wf$lines)
    present <- PR_GATED_JOBS[PR_GATED_JOBS %in% names(blocks)]
    if (length(present) == 0L) {
      fail("RED U4: no build-*/migrate/liquibase-dev/deploy jobs found in deploy.yml to assert PR gating.")
    } else {
      for (j in present) {
        gated <- grepl("github\\.event_name\\s*!=\\s*['\"]pull_request['\"]", blocks[[j]]) ||
          grepl("github\\.event\\.pull_request", blocks[[j]])
        if (!gated) {
          fail(paste0(
            "RED U4: creds-needing job `", j, "` has no PR gate.",
            " Writer must gate it with `if: github.event_name != 'pull_request'` (or a github.event.pull_request equivalent)."
          ))
        }
      }
      expect_true(TRUE)
    }
  }
})

test_that("Trivy fs + config (misconfig) scans present as required jobs/steps with SARIF", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert Trivy fs/config scans.")
  } else if (!grepl("trivy", wf$text, ignore.case = TRUE)) {
    fail("RED U4: deploy.yml has no trivy steps. Writer must add Trivy fs + config (misconfig) scans as required jobs/steps (e.g. aquasecurity/trivy-action).")
  } else {
    expect_match(
      wf$text, "trivy",
      info = "RED U4: deploy.yml must reference trivy."
    )
    if (!grepl("\\bfs\\b", wf$text)) {
      fail("RED U4: no Trivy `fs` scan in deploy.yml. Writer must add a filesystem scan (scan-type: fs / scan-ref).")
    }
    if (!grepl("config|misconfig", wf$text, ignore.case = TRUE)) {
      fail("RED U4: no Trivy config/misconfig scan in deploy.yml. Writer must add an IaC misconfig scan (scan-type: config).")
    }
    expect_match(
      wf$text, "sarif",
      info = "RED U4: Trivy fs/config scans must emit SARIF (`format: sarif` or a SARIF upload step) so findings are visible."
    )
  }
})

test_that("Trivy image scans for ETL + Shiny images present and ADVISORY (never blocking)", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert Trivy image scans.")
  } else if (!grepl("trivy", wf$text, ignore.case = TRUE)) {
    fail("RED U4: deploy.yml has no trivy steps. Writer must add Trivy IMAGE scans for the built ETL + Shiny images in ADVISORY mode (SARIF, non-blocking) until I5.")
  } else {
    if (!grepl("image-ref|image_ref|scan-type:\\s*['\"]?image", wf$text, ignore.case = TRUE) &&
      !grepl("trivy.*image|image.*trivy", wf$text, ignore.case = TRUE)) {
      fail("RED U4: no Trivy image scan in deploy.yml. Writer must scan the built ETL + Shiny images (image-ref) in advisory mode.")
    }
    has_etl <- grepl("ETL_IMAGE_BASE|Dockerfile\\.etl|yt-sailing-channel-etl", wf$text)
    has_shiny <- grepl("SHINY_IMAGE_BASE|Dockerfile\\.shiny|yt-sailing-shiny", wf$text)
    if (!(has_etl && has_shiny)) {
      fail("RED U4: Trivy image scans must cover BOTH the ETL and Shiny images (ETL_IMAGE_BASE/Dockerfile.etl + SHINY_IMAGE_BASE/Dockerfile.shiny).")
    }
    expect_false(
      grepl("exit-code:\\s*['\"]?1['\"]?", wf$text),
      info = "RED U4: Trivy is ADVISORY until I5 — no `exit-code: '1'` / `exit-code: 1` blocking gate allowed on trivy steps."
    )
    expect_false(
      grepl("severity:[^\\n]*CRITICAL[^\\n]*\\n[^\\n]*exit-code", wf$text, ignore.case = TRUE) &&
        grepl("exit-code:\\s*['\"]?1['\"]?", wf$text),
      info = "RED U4: no blocking severity gate on trivy steps (advisory-first per OQ-7, enforcing in I5)."
    )
  }
})

test_that("SARIF upload step present (findings visible while check stays green)", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert SARIF upload.")
  } else if (!grepl("upload-sarif", wf$text, ignore.case = TRUE)) {
    fail("RED U4: no SARIF upload step in deploy.yml. Writer must add github/codeql-action/upload-sarif (or equivalent) so Trivy findings reach code scanning while the check stays green.")
  } else {
    expect_match(
      wf$text, "upload-sarif",
      info = "RED U4: deploy.yml must include a SARIF upload step."
    )
  }
})

test_that("required-checks documentation exists (workflow comments or docs/ note)", {
  wf <- read_workflow()
  if (is.null(wf)) {
    fail("RED U4: .github/workflows/deploy.yml missing, cannot assert required-checks docs.")
  } else {
    doc_paths <- c(
      file.path(here("docs"), "required-checks.md"),
      file.path(here("docs"), "pr-checks.md"),
      file.path(here("docs"), "branch-protection.md")
    )
    docs_hit <- FALSE
    for (p in doc_paths) {
      if (file.exists(p)) {
        docs_hit <- TRUE
        break
      }
    }
    if (!docs_hit && dir.exists(here("docs"))) {
      candidates <- list.files(here("docs"), pattern = "\\.md$", recursive = TRUE, full.names = TRUE)
      for (f in candidates) {
        txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
        if (grepl("required.*check|check.*required", txt, ignore.case = TRUE)) {
          docs_hit <- TRUE
          break
        }
      }
    }
    workflow_hit <- grepl("required", wf$text, ignore.case = TRUE)
    if (!(docs_hit || workflow_hit)) {
      fail(paste(
        "RED U4: required checks undocumented. Writer must list the required checks",
        "(testthat, lintr, ruff, terraform fmt/validate, Trivy fs + config + image)",
        "in workflow comments or a docs/ note (e.g. docs/required-checks.md)."
      ))
    }
    combined <- wf$text
    if (docs_hit && dir.exists(here("docs"))) {
      candidates <- list.files(here("docs"), pattern = "\\.md$", recursive = TRUE, full.names = TRUE)
      for (f in candidates) {
        combined <- paste(combined, paste(readLines(f, warn = FALSE), collapse = "\n"), sep = "\n")
      }
    }
    expect_match(
      combined, "[Aa]dvisory|[Uu]ntil I5|I5",
      info = "RED U4: required-checks docs must state Trivy is advisory-until-I5 (enforcing in I5 per OQ-7)."
    )
  }
})

test_that("no pipeline behavior change: etl/shiny/sql/scripts untouched except 1B-U1 backup hook", {
  # 1B-U1 ALLOWLIST (approved plan agents/plans/iteration_1b_plan.md): that
  # unit legitimately adds a 9-line step-6 backup hook to etl/main.R plus the
  # new scripts/backup_source_tables.R. Both paths are allowlisted here;
  # anything else under etl//shiny//sql//scripts/ must still FAIL.
  out <- tryCatch(
    system2("git", c("diff", "--name-only", "HEAD"), stdout = TRUE, stderr = TRUE),
    error = function(e) e
  )
  if (inherits(out, "error")) {
    fail(paste0("RED U4: `git diff --name-only HEAD` failed: ", conditionMessage(out)))
  } else {
    changed <- trimws(out[nzchar(trimws(out))])
    protected <- changed[grepl("^(etl|shiny|sql|scripts)/", changed)]
    # NOTE: config.yml carries a PRE-EXISTING modification (out of U4 scope)
    # and is deliberately excluded from this assertion.
    allowed_files <- c("scripts/backup_source_tables.R", "etl/main.R")
    unexpected <- setdiff(protected, allowed_files)
    expect_equal(
      length(unexpected), 0L,
      info = paste(c(
        "RED U4: pipeline behavior change detected — U4 must touch CI/docs only (plus the 1B-U1 backup-hook allowlist), never other etl//shiny//sql//scripts/ files:",
        unexpected
      ), collapse = "\n")
    )
    if ("etl/main.R" %in% protected) {
      # NARROW allowlist: etl/main.R may carry ONLY the 1B-U1 step-6 backup
      # hook (add-only). Every added line must belong to that hook; any
      # removed line or any foreign added line FAILs.
      hunks <- tryCatch(
        system2("git", c("diff", "HEAD", "--", "etl/main.R"), stdout = TRUE, stderr = TRUE),
        error = function(e) e
      )
      if (inherits(hunks, "error")) {
        fail(paste0("RED U4: `git diff HEAD -- etl/main.R` failed: ", conditionMessage(hunks)))
      } else {
        added <- hunks[grepl("^\\+", hunks)]
        added <- added[!grepl("^\\+\\+\\+", added)]
        removed <- hunks[grepl("^-", hunks)]
        removed <- removed[!grepl("^---", removed)]
        if (length(removed) > 0L) {
          fail(paste(c(
            "RED U4: etl/main.R has REMOVED lines outside the 1B-U1 allowlist (the step-6 backup hook is add-only):",
            removed
          ), collapse = "\n"))
        }
        stripped <- sub("^\\+", "", added)
        ok <- grepl(
          "backup_source_tables|run_backup|[Ss]tep 6|tryCatch|warning\\(|message\\(|source\\(here|connection, project, dataset|error\\s*=\\s*function|^\\s*$|^\\s*#|^\\s*[}\\)][}\\)\\s,]*$",
          stripped
        )
        if (!all(ok)) {
          fail(paste(c(
            "RED U4: etl/main.R has added lines outside the 1B-U1 step-6 backup-hook allowlist (only the backup hook may touch this file):",
            added[!ok]
          ), collapse = "\n"))
        }
        expect_true(TRUE)
      }
    }
  }
})

test_that("U1/U2/U3 regression: gate files and baseline scripts intact", {
  must_exist <- c(
    here("tests", "testthat", "test_lint_gates.R"),
    here("tests", "testthat", "test_terraform_adopt.R"),
    here("tests", "testthat", "test_liquibase_sql.R"),
    here(".lintr.R"),
    here("pyproject.toml"),
    here("etl", "Dockerfile.etl"),
    here("shiny", "Dockerfile.shiny")
  )
  missing <- must_exist[!file.exists(must_exist)]
  if (length(missing) > 0L) {
    fail(paste(
      "RED U4: U1/U2/U3 gate files missing (writer must not break prior units):",
      paste(missing, collapse = ", ")
    ))
  }
  expect_true(TRUE)
})
