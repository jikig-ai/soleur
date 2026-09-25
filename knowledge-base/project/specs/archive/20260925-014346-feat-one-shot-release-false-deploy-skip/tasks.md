---
title: "Tasks: resolve-target must not clean-skip a deploy on an empty runs lookup"
branch: feat-one-shot-release-false-deploy-skip
plan: knowledge-base/project/plans/2026-09-24-fix-release-resolve-target-false-deploy-skip-plan.md
lane: cross-domain
---

# Tasks: resolve-target false deploy skip

Derived from the finalized, deepened plan. PR #8770; no issue.

## Phase 1: Setup and baselines

- [ ] 1.1 Re-run the baselines:
  - `resolve-target-decision.test.sh` (24/24);
  - `workflow-run-deploy-invariants.test.sh` (70/70);
  - `deploy-arm.test.sh`;
  - `prod-version-drift-check.test.sh`;
  - `c4-count-parity.test.sh`;
  - `python3 scripts/lint-workflow-errexit-capture.py`.
- [ ] 1.2 Write the harness changes first, RED before the fix (`cq-write-failing-tests-before`):
  - [ ] 1.2.1 Change `get()` to `tail -1`, and assert exactly one `^skip_reason=` line.
  - [ ] 1.2.2 `source test-helpers.sh` below the existing EXIT trap, then call
    `git_fixture_env "$W"`. A failed CONTROL exits **2**, rewritten as `if ( … ); then`.
  - [ ] 1.2.3 Build the linear source repo `$W/src` with the commits `root`, `docs`, `app`,
    `pdocs`, `ptest` and `mvout`. Add `mkshallow <sha>`: a depth-1 clone with a `file://`
    `origin`.
  - [ ] 1.2.4 `run_resolve` always runs the body with `cd` into a clone (default: the `app`
    clone). It truncates `sleep.log` on every call.
  - [ ] 1.2.5 Move CONTROL to the `app` commit, with its artifact built from that SHA.
  - [ ] 1.2.6 Extend the `gh` stub:
    - the `head_sha` route first, with an optional sequence served by `$FIX/.n_filtered`;
    - any other `runs?` → `runs_all.json`;
    - fixtures carry `head_branch`;
    - `mkfix` writes `runs_all.json`.
  - [ ] 1.2.7 Add a `sleep` stub that logs to `$W/sleep.log`.
  - [ ] 1.2.8 The extractor reads `env.RELEASE_PATH_FILTER` from the YAML, and `run_resolve`
    passes it through.
  - [ ] 1.2.9 Add rows S1, L1, L2 (own `FIXDIR`), L3, L5, L6, L7, L8, L9, A1b, A2, A2b and X2,
    including the branch-specific stdout assertions and the `lookup_path`/`::warning::`
    assertions. Confirm they are RED against the current workflow.

## Phase 2: Core implementation (`.github/workflows/web-platform-release.yml`)

- [ ] 2.1 Leave the resolve-target checkout **unchanged** (depth 1, because `deploy-arm.sh`
  keys on `--depth=1 origin <sha>`). Only add the comment.
- [ ] 2.2 Step `resolve` env: add `RELEASE_PATH_FILTER`, byte-identical to
  `jobs.release.with.path_filter`. Job outputs: add `lookup_path`.
- [ ] 2.3 Preamble: `shopt -s inherit_errexit` and `exec 3>&1`. Every annotation in
  `fail_closed`/`clean_skip` goes to `>&3`.
- [ ] 2.4 Lookup loop, written as plain statements:
  - [ ] 2.4.1 Keep the primary filtered read unchanged (the G7 literal).
  - [ ] 2.4.2 Add the unfiltered fallback with
    `select(.event == "push" and .head_branch == "main" and .head_sha == $sha)`.
  - [ ] 2.4.3 4 lookups, `sleep 20` between them, the `lookup N/4` log line, and a break on
    found.
  - [ ] 2.4.4 Numeric run-id check. Emit the `lookup_path` output, and a `::warning::` (to
    `>&3`) when the run is found only after a retry or via the fallback.
- [ ] 2.5 Lazy deepen: `git cat-file -e <sha>~1^{commit}`, otherwise
  `git fetch --no-tags --depth=2 origin <sha>`. Then run the diff under `set -f` with the
  `|| _drc=$?` capture, and `set +f`:
  - rc ≠ 0 → `fail_closed` with `release_run_missing` (include git's stderr);
  - non-empty output → `fail_closed` with `release_run_missing`, listing the filenames with CR
    stripped, `%` escaped to `%25` and a 300-byte cap;
  - otherwise → `clean_skip` with `no_release_run`.
- [ ] 2.6 `notify-gated`:
  - the `if:` conjunct;
  - the `case` CAUSE (Re-run failed jobs; wait about 15 min on a repeat; do not re-run the push
    arm);
  - the trailer that depends on the reason.
- [ ] 2.7 Comments: the FIVE STATES table (row 1 plus the new row), STATE 1 (the push run
  exists first), the liveness-poll note, the `timeout-minutes` note, the checkout depth-1
  reason.

## Phase 3: Consumers and records

- [ ] 3.1 `workflow-run-deploy-invariants.test.sh`:
  - [ ] 3.1.1 Add P1 (pathspec parity), P2 (checkout has no `fetch-depth`, or `fetch-depth: 1`)
    and P3 (`on.push.paths` → pathspec equals `path_filter`; read `d.get(True)` for `on:`).
  - [ ] 3.1.2 G8 accepts `.event == "push"`; add the must-PASS and must-RED rows.
  - [ ] 3.1.3 Update the G7 "five states" comment, and raise the floor (`TOTAL=`/`MIN_ROWS=`
    stay adjacent).
- [ ] 3.2 Raise the floor in `resolve-target-decision.test.sh` and update its derivation
  comment.
- [ ] 3.3 `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`: add the
  `release_run_missing` state.
- [ ] 3.4 `.github/workflows/scheduled-prod-version-drift.yml`: add one remediation line naming
  `release_run_missing`.
- [ ] 3.5 ADR-217:
  - a `> **Addendum (2026-09-24).**` under §3;
  - the §3 table rows;
  - the run-discovery (locator-only) step in the §2 trust ladder;
  - Consequence 4's counts taken from G9's extractor output;
  - add `resolve-target-decision.test.sh` to References;
  - name the three-way pathspec coupling.

## Phase 4: Verification

- [ ] 4.1 All suites green: decision, invariants, `deploy-arm.test.sh`, drift-check (B8/B9),
  C4 count parity, errexit lint (AC1, AC3, AC5, AC6, AC7, AC10).
- [ ] 4.2 Check AC9's anchored greps (1 / 1 / 2) and AC11 (`fetch-depth` count 0 in the
  resolve-target block).
- [ ] 4.3 Run Guard 1 mutations 1–8, Guard 2 mutations 1–7 and harness rows H1/H3/H5 once, on
  scratch copies. For each, record the PyYAML region-diff landing check, CONTROL passing, and the
  named row in `FAILURES`, as the PR-body evidence table (AC4).
- [ ] 4.4 `npx markdownlint-cli2` on the changed markdown.
- [ ] 4.5 Post-merge (AC12): `bash plugins/soleur/scripts/deploy-arm.sh find --wait <MERGE_SHA>`
  identifies the merge's deploy arm, and it reaches `deploy: success` with `release run: <id>` in
  its log.
