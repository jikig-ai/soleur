# Learning: "No test asserts X" for a workflow/config file must grep step-names across `*.test.sh`, not just snapshot tests

## Problem

Migrating the release notification from a "Post to Discord (release)" step to "Post to Slack (release)"
in `.github/workflows/reusable-release.yml`, the brainstorm's Explore agent and the plan's Research
Reconciliation both asserted **"No tests assert the Discord step (idempotency test only)."** That was a
false-negative: `plugins/soleur/test/reusable-release-idempotency.test.sh` **T6** asserts that BOTH
`Email notification (release)` AND `Post to Discord (release)` fire on the orphaned-draft self-heal path
(#4902) — it `awk`s the workflow for each step's literal name and checks the `if:` disjunct.

The miss surfaced only at the **work Phase 2 full-suite / orphan-suite exit gate** (`reusable-release-idempotency.test.sh` returned 10/11, T6 FAIL) — not at any earlier gate, because the touched-file
test loop never runs it (it's a sibling suite, not co-named with the workflow).

## Solution

Updated T6 to assert `Post to Slack (release)` (and the comment/echo Discord→Slack). 11/11 pass.

## Key Insight

When claiming "no test asserts X" for a **workflow or config file** (`.yml`, `.toml`, `.gitleaks.toml`),
the search must cover **CI-workflow tests that assert on step/field names via `awk`/`grep`** — these live
in `*.test.sh` and key off literal strings inside the file, not on a snapshot or an `import`. A search
scoped to snapshot/assertion-style unit tests returns a confident false-negative. Cheapest gate at
plan/research time: `git grep -l "<exact step name or field literal>" -- '**/*.test.sh' 'plugins/**/test/**' 'apps/**/test/**'` before asserting "nothing asserts it." This is also a vindication of the
work-skill's orphan-suite exit gate (`bash scripts/test-all.sh` / sibling-suite run) — it caught what
every upstream gate missed. Related: [[2026-06-09-move-request-conceals-scope-fork-verify-the-actual-complaint]].

## Tags
category: test-failures
module: work
