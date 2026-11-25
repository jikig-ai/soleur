# Tasks — fix #13051: cf-account-migrate-job.test.sh CI bound and signal trap

Plan: `knowledge-base/project/plans/2026-11-25-fix-cf-migrate-job-suite-ci-bound-plan.md`

## 1. Setup

- 1.1 Re-run the suite once on this branch and keep the log (`stepA-baseline.log`) for later comparison.
- 1.2 Time one plain apply job without xtrace, before any change (`date +%s%N` around `run_job` in a scratch copy).

## 2. Signal handling (Phase 1, tests first)

- 2.1 Print `[sandbox] <path>` to stderr right after `mktemp`.
- 2.2 Add the `CFAM_JOB_SIGTEST` seam right after the trap registration, before the instrument self-test.
- 2.3 Add the self-test parent rows: start the child with `set -m`, poll for `armed` (max 20 s), send `kill -TERM -- -<pgid>`, then assert rc 143, one `[ABORTED]`, no `SIGTEST-RESUMED`, no `^  FAIL: SIGTEST` line, and the sandbox gone.
- 2.4 Resolve `timeout`/`gtimeout`/`SOLEUR_TIMEOUT_BIN` for AC3. A missing binary fails under CI and is a counted SKIP elsewhere.
- 2.5 Confirm the self-test goes RED against today's trap (Guard 1 row 1).
- 2.6 Replace the trap: the EXIT trap cleans; the TERM/INT/HUP handler prints `[ABORTED]` and exits 128+n.
- 2.7 Run Guard 1 mutation rows 1-3 against scratch copies and record the commands (AC2).
- 2.8 Bump `EXPECTED_CASES`.

## 3. Slim workspace and stall cut (Phase 2)

- 3.1 Add `derive_reach`, and leave `GATED_FILE` byte-identical.
- 3.2 Build `$SBX/ws-slim`, with a `[FATAL]` exit when its workflow count differs from `|reach|` or is 0.
- 3.3 Default `run_job`'s `GITHUB_WORKSPACE` to `ws-slim`, and record the workspace per case dir.
- 3.4 Point `$MIRROR/.github` at `ws-slim/.github`.
- 3.5 Append `GITHUB_WORKSPACE=$REPO` after setup in the `[inflight]` inline rows. Re-run the derivation-mutant grep.
- 3.6 Add the parity row (`inflight=none workflows=${N_GATED}` over `ws-slim`).
- 3.7 Change the stall stub from `exec sleep 40` to `exec sleep 12`, with an inequality comment (12 > 8).
- 3.8 Add `CFAM_KEEP_SBX=1`, the workspace on the `fail()` line, and the `# HARNESS` authoring contract.
- 3.9 Re-time the plain job without xtrace and record before and after.
- 3.10 Full local run green (AC1). Regenerate the `fixture-relative-assert` baseline row, and run the AC10 suites.

## 4. Measure and gate (Phase 3)

- 4.1 Push. Download `suite-timings-infra-*` for this PR's runs (at least 2) and take the worst figure for this suite.
- 4.2 If the worst figure is over 360000 ms, go to section 5. Otherwise, record that the gate passed and skip section 5.
- 4.3 Edit only this suite's row in `apps/web-platform/infra/suite-durations.tsv` (`measured`).
- 4.4 Run `regenerate-shard-manifest.py --group infra --durations apps/web-platform/infra/suite-durations.tsv` as a dry run. Paste the leg table into the PR body. Then run it with `--write --allow-growth` and state the reason.
- 4.5 Rewrite the `_SUITE_BOUNDS` comment: worst figure, ratio, PR number, re-measure recipe, and both revisit triggers (AC8).
- 4.6 Re-run the legs and record each leg's wall time in the PR body (recorded, not gated).

## 5. Row pool (Phase 4, only if the gate trips)

- 5.1 Capture the golden label list from the Step A serial run.
- 5.2 Write the pool-mode self-test first (a direct `kill -TERM <pid>` to the suite alone after `armed`, then `kill -0` on the recorded SUT PIDs).
- 5.3 Build the whole-row subshell pool. Setups stay in the parent, rows write to a file, the flush drains every row and prints in order, `run_job` flushes first, `^SECONDS=` rows run in the foreground, `CFAM_MUT_JOBS` takes 1-8, and the `section` helper replaces the headers.
- 5.4 Add the Guard 3 rows, including the comparison of `$SBX` top-level and `$SBX/bin` listings.
- 5.5 Diff the pooled run against the golden list (AC5). Then return to 4.1.

## 6. Ship prep

- 6.1 AC9 diff check (no token or `ssh` lines).
- 6.2 PR body: the run table, the measurements, the gate outcome, the leg table, and `Closes #13051`. Reference #13055 and #12958 (rebase notes).
