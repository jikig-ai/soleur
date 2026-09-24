---
title: "Tasks: resolve-target must not clean-skip a deploy on an empty runs lookup"
branch: feat-one-shot-release-false-deploy-skip
plan: knowledge-base/project/plans/2026-09-24-fix-release-resolve-target-false-deploy-skip-plan.md
lane: cross-domain
---

# Tasks: resolve-target false deploy skip

Derived from the finalized (post-review) plan. PR #8770; no issue.

## Phase 1: Setup and baselines

- [ ] 1.1 Re-run the baselines: `resolve-target-decision.test.sh` (24/24),
  `workflow-run-deploy-invariants.test.sh` (70/70), `prod-version-drift-check.test.sh`,
  `c4-count-parity.test.sh`, and `python3 scripts/lint-workflow-errexit-capture.py`.
- [ ] 1.2 Write the harness changes before the fix (RED first, `cq-write-failing-tests-before`):
  - [ ] 1.2.1 Make `get()` read `tail -1`, and add the assertion that exactly one
    `^skip_reason=` line exists.
  - [ ] 1.2.2 `source test-helpers.sh` below the existing EXIT trap; call `git_fixture_env "$W"`;
    rewrite CONTROL as `if ( … ); then`.
  - [ ] 1.2.3 Build one linear fixture repo with the commits `root`, `docs`, `app`, `pdocs`,
    `ptest` and `mvout`.
  - [ ] 1.2.4 Extend the `gh` stub: the `head_sha` route first, with an optional sequence served
    by `$FIX/.n_filtered`, then the other `runs?` route → `runs_all.json`. `mkfix` writes
    `runs_all.json`.
  - [ ] 1.2.5 Add a `sleep` stub that logs to `$W/sleep.log`.
  - [ ] 1.2.6 Have the extractor read `env.RELEASE_PATH_FILTER` from the YAML; `run_resolve`
    passes it and runs in `CWD=${GITDIR:-$W}`.
  - [ ] 1.2.7 Add rows S1 (moved onto the repo), L1 (the requested row), L2, L3, L5, L6, L7, L8,
    A2 and X2, then confirm they are RED against the current workflow.

## Phase 2: Core implementation (`.github/workflows/web-platform-release.yml`)

- [ ] 2.1 `resolve-target` checkout: add `fetch-depth: 2` (keep the `ref:` pin).
- [ ] 2.2 Step `resolve` env: add `RELEASE_PATH_FILTER`, byte-identical to
  `jobs.release.with.path_filter`.
- [ ] 2.3 At the top of the step body, add `shopt -s inherit_errexit` and `exec 3>&1`. Send the
  `fail_closed`/`clean_skip` annotations to `>&3`.
- [ ] 2.4 Lookup loop in plain statements:
  - [ ] 2.4.1 Keep the primary filtered read unchanged (G7 literal).
  - [ ] 2.4.2 Add the unfiltered fallback with
    `select(.event == "push" and .head_sha == $sha)`.
  - [ ] 2.4.3 4 lookups, `sleep 20` between them, the `lookup N/4` log line, and a break on
    found.
- [ ] 2.5 Diff check: `set -f`, `git diff --no-renames --name-only <sha>~1 <sha> -- $RELEASE_PATH_FILTER`
  with the `|| _drc=$?` capture, then `set +f`. Fail closed with `release_run_missing` on rc ≠ 0 or
  non-empty output; otherwise clean-skip with `no_release_run`.
- [ ] 2.6 `notify-gated`: add the `if:` conjunct, the `case` CAUSE (Re-run failed jobs, wait
  about 15 min on a repeat, do not re-run the push arm), and the trailer that depends on the
  reason.
- [ ] 2.7 Comments: the FIVE STATES table (row 1 plus the new row), STATE 1 (the
  push-run-exists-first assumption), the liveness-poll note, the `timeout-minutes` note.

## Phase 3: Consumers and records

- [ ] 3.1 `workflow-run-deploy-invariants.test.sh`:
  - [ ] 3.1.1 Add P1 (pathspec parity) and P2 (`fetch-depth` of 0 or ≥ 2).
  - [ ] 3.1.2 G8 accepts `.event == "push"`; add the must-PASS and must-RED rows.
  - [ ] 3.1.3 Raise the floor (`TOTAL=` and `MIN_ROWS=` stay adjacent to the `if`).
- [ ] 3.2 Raise the floor in `resolve-target-decision.test.sh` and update its derivation comment.
- [ ] 3.3 `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`: add the
  `release_run_missing` state.
- [ ] 3.4 ADR-217: add `## Amendment — 2026-09-24` and fix the §3 table row 1.

## Phase 4: Verification

- [ ] 4.1 All suites green: decision, invariants, drift-check (B8/B9), C4 count parity, errexit
  lint (AC1, AC3, AC5, AC6, AC7).
- [ ] 4.2 Check AC9's anchored greps: 1 / 1 / 2.
- [ ] 4.3 Run the Guard 1 mutations 1–7 and Guard 2 mutations 1–5 once, each as a sed on a
  scratch copy with a `cmp -s` landing check. Also run harness rows H1/H3. Record the evidence
  table for the PR body (AC4).
- [ ] 4.4 `npx markdownlint-cli2` on the changed markdown.
- [ ] 4.5 Post-merge (AC10): the merge SHA's deploy arm, identified by the
  `resolving deploy target for <sha>` log line, reaches `deploy: success`.
