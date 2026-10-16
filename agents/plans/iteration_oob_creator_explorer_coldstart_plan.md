# OOB Iteration — Creator Explorer Cold-Start Crash — Delivery Plan

Status: **DRAFT — 2026-10-16**
Date: 2026-10-16
Author: Orchestrator

---

## 1. Executive Summary

Fix the `Channel Explorer` crash seen when querying a channel freshly added
via `scripts/add_channel.py` (reported: `UCut5i0tjCW-5Bg_mJtS-eRg`,
`missing value where TRUE/FALSE needed` in `output$channel_dashboard_ui`).
Root cause is a **cold-start gap**: `add_channel.py` inserts an
identity-only `channel_dimensions` row (no title/meta, no history); until
1–2 ETL runs enrich it, flow metrics (`daily_new_views`,
`views_moving_avg_7d`) are `NULL`/absent, and the footnote guard at
`shiny/pages/creator_explorer.R:284-289` evaluates `if (NA)`.

Implementation: presentation-layer hardening only in `shiny/` (plus
testthat coverage). No SQL/ETL/medallion changes — single-row `NULL`s are
correct data; the dashboard must tolerate them. TDD per unit:
tester (red) → writer (green) → verifier (gate PASS/FAIL).

Deliverables:
0. U1 — Testable cold-start helpers + red-baseline tests
   (`safe_tail`, footnote predicate, profile-field coalescing).
1. U2 — `creator_explorer.R` graceful-partial UI: header always renders
   with `N/A` placeholders + populating-notice banner; charts/value boxes
   degrade on `NA`/empty history instead of crashing.

Explicitly out of scope: `add_channel.py`, `insert_channel_dim.sql`, ETL
order/scheduling, `fct_daily_performance.sql` windowing, backfills,
migrates, cache-refresh timing changes, hoisting `renderPlotly` out of
`renderUI` (noted as follow-up only).

**Key constraint(s) honored throughout:** Medallion one-way flow unchanged;
`shiny/` reads BigQuery + GCS cache, never writes (AGENTS.md Layer Rules);
`channel_id` truth (BR-006); ETL failures never deactivate (BR-013);
health observes only (BR-019); admin never the data store (NFR-010);
dataset discipline — dev-BQ verification only, prod verified by the user.

---

## 2. Architecture-Gate Check (all units)

Reference: AGENTS.md Architecture Gate + `docs/component_diagram.puml`
(existing pipeline) + README §Architecture & Data Lineage.

| Unit | Calls | Must NOT call | Verdict |
|---|---|---|---|
| U1 | New/test R helpers (pure functions, no reactivity) | BigQuery/GCS writes; ETL/`sql/` behavior change | PASS |
| U2 | `channel_profile()` / `channel_history()` reactives (read-only), existing `format_dashboard_value()` | BigQuery writes; new marts/tables; admin-panel logic in Shiny (OQ-1); upstream medallion writes | PASS |

No pipeline behavior change; no new data store; every mutation path
untouched (nothing here mutates, so BR-016/NFR-002 trivially hold).

---

## 3. Units of Work (serialized)

### U1 — Cold-start helpers + red-baseline tests

**Goal:** Crash predicate and field-coalescing logic live in pure,
testable functions so the `if (NA)` class of bug is pinned by tests.

**Deliverables:**

- New helper source (location: `shiny/utils/coldstart_helpers.R`, sourced
  from `shiny/global.R` beside the other `utils/` sources):
  - `safe_tail1(x)` — returns `x`'s last element or `NA_real_` on
    `NULL`/empty.
  - `show_negative_note(...)` — footnote predicate: `length > 0 &&
    isTRUE(any(vals < 0, na.rm = TRUE))`. Never returns `NA`.
  - `coalesce_profile_field(x, fallback = "N/A")` — `NULL`/`NA`/empty →
    fallback (covers 0-row profile `NULL` vs 1-row `NA` uniformly).
- New tests `tests/testthat/test_creator_explorer_coldstart.R`:
  - Single-row all-`NA` flow metrics → `show_negative_note()` is `FALSE`,
    no error (exact reported crash).
  - Empty vectors → predicate `FALSE`; `safe_tail1()` is `NA`.
  - `NULL` vs `NA` profile fields → fallback, never `logical(0)` into `if`.
  - Mixed `c(5, NA)` → `FALSE`; `c(-1, NA)` → `TRUE` (no `NA` leak).

**Conventions:** R code only; comments per `class_comment_specification.md`;
no Shiny reactivity inside helpers (pure inputs → pure outputs).

**Test surface (tester writes first):** all cases above red on current
inline logic, green after helpers land.

**Verification:** `Rscript tests/testthat.R` green.

**Dependencies:** none. **Architecture gate:** PASS.

### U2 — Graceful-partial Creator Explorer UI

**Goal:** A newly added channel renders a useful partial page instead of
crashing: profile header with placeholders + notice, charts/values
degraded.

**Touchpoints:**
- Modified: `shiny/pages/creator_explorer.R` only.
- New (from U1): `shiny/utils/coldstart_helpers.R`.
- Modified (1 line): `shiny/global.R` (`source()` the helper).
- Forbidden: `etl/`, `sql/`, `scripts/add_channel.py`, cache-refresh
  timing, prod dataset.

**Flow (agreed UX: graceful partial):**
1. Pull `prof <- channel_profile(); hist <- channel_history()` once at
   top of `renderUI` (after existing `req(input$selected_channel)`).
2. Empty-history branch: `if (is.null(hist) || nrow(hist) == 0)` return
   `tagList(profileHeader, populatingNotice)` — no plots, no value boxes,
   no footnote evaluation.
3. Profile header: all fields via `coalesce_profile_field()`; `status`/
   `type` keep existing "Sailing"/"Sailing Vlog" fallbacks through the
   helper (fixes both `is.na(NA)` and `is.na(NULL)` paths at lines
   172/178); YouTube link guarded when handle is missing.
4. Value boxes: all four route through `format_dashboard_value()` /
   `safe_tail1()` so single-row `NA`s show `"N/A"`, never `"NA"`/blank.
5. Charts: skip `plot_ly` trace when the column is empty/all-`NA`;
   render a muted "insufficient history" placeholder in the showcase.
6. Footnote: replace bare `if (any(...))` with
   `if (show_negative_note(...))` (U1 predicate).
7. Notice banner content: "Channel recently added — metrics populating;
   check back after the next ETL run." Shown whenever history is
   empty OR all flow-metric columns are `NA` (single-row cold start),
   while still rendering the header + available stock metrics.

**Test surface (tester extends U1 file or adds UI-logic tests):**
- Predicate/branch selection is unit-tested via helpers (U1); U2 adds a
  logic test that the empty-history branch condition fires on 0-row
  input and does not evaluate the footnote expression.
- No live-Shiny integration test (no harness configured); manual
  stub-repro steps documented in the plan (§5).

**Verification:** `Rscript tests/testthat.R` green; stub-repro (0-row +
1-row-`NA` reactives) renders without the `if` error and shows the
banner; dev-BQ spot check (§5). User verifies prod.

**Dependencies:** U1 (helpers). **Architecture gate:** PASS.

---

## 4. Dependency Order & Execution

```
U1 (helpers + red tests) ─→ U2 (UI wiring, green)
```

U1 first so U2 wires frozen, tested predicates. TDD loop per unit:
tester (red baseline) → writer (green) → verifier (gate PASS/FAIL).
Fail routing: code issue → writer; test issue → tester. Two identical
failed loops → stop and surface to user.

---

## 5. Verification Strategy

Per-unit gate:

| Unit | Command(s) |
|---|---|
| U1 | `Rscript tests/testthat.R` green (new cold-start tests) |
| U2 | `Rscript tests/testthat.R` green + stub-repro (0-row / 1-row-`NA`) renders banner, no `if` error |

Pre-fix confirm (read-only, **dev dataset only** — `DATASET` confirmed
from `config.yml` first): `get_channel_profile.sql` +
`get_channel_history.sql` for `UCut5i0tjCW-5Bg_mJtS-eRg`; expect
identity-only dim row (`NULL` title/meta) and 0–1 history rows with
`NULL` flow metrics. Also note whether the ETL has run since the add
and whether hourly `reactivePoll` (`shiny/server.R`) has picked the
channel into `channel_info.rds`.

Final regression (once, after U2): full `Rscript tests/testthat.R`
green; `git status` shows only the 3 touched files (helper, 1-line
`global.R` source, `creator_explorer.R`) + 1 test file; no `etl/`,
`sql/`, `scripts/` diffs. **Prod check is the user's** (no prod access
granted).

## 6. Decisions & Open Questions

### Resolved (user-confirmed 2026-10-16)

| # | Question | Decision |
|---|---|---|
| OOB-C1 | Cold-start UX | Graceful partial: header + placeholders + notice banner; charts degrade |
| OOB-C2 | Verification scope | Dev-BQ read-only checks allowed; prod verification by the user |

### Open

- None — ready for review. On approval: build U1 → U2 under the TDD loop
  above; record the shipment in `agents/iteration_history.md` on completion.
- Follow-up (not this OOB): hoist the four `renderPlotly` outputs out of
  `renderUI`; revisit `channel_info.rds` freshness UX for just-added
  channels (hourly poll vs manual refresh note).
