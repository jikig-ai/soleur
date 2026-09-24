# Tasks: cancel superseded PR runs

Plan: `knowledge-base/project/plans/2026-09-24-ci-cancel-superseded-pr-runs-plan.md`
(PR #8669; never `--admin` merge: UNTRUSTED-CI).

## Phase 1: Setup

- [ ] 1.1 Re-verify the live API shapes the plan depends on. Check the run object fields
  (`id`, `event`, `head_branch`, `head_sha`, `created_at`, `status`, `path`,
  `head_repository.full_name`) for pull_request, pull_request_target and dynamic runs. Check the
  `gh api -i` status-line format on a no-op 409 cancel against a completed run.
- [x] 1.2 Read `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` (the gh-stub pattern) and
  `.github/scripts/test/run-all.sh` (the contract and the `MIN_SUITES` floor).

## Phase 2: Tests first (RED)

- [x] 2.1 Create `.github/scripts/test/test-cancel-superseded-pr-runs.sh`, bash-only with an
  assertion floor.
  - [ ] 2.1.1 Selection layer: rows S0a-S13, plus S4j, S7b and S9b, covering both sides of
    every rule.
  - [ ] 2.1.2 Orchestration layer: a stubbed `gh` with a per-call head sequence and a call log,
    rows O1-O16 and O5e. Cover:
    - A→B→A;
    - the head check running after both list calls;
    - no `status=`, but `created>=` present;
    - URL encoding of `feat/x y`;
    - an empty listing;
    - the dry run;
    - no `force-cancel`.
  - [ ] 2.1.3 Confirm the suite is RED against a missing script.
- [x] 2.2 Bump `MIN_SUITES` 12 → 13 in `.github/scripts/test/run-all.sh`, with a provenance
  sentence.

## Phase 3: Core implementation (GREEN)

- [x] 3.1 Create `.github/scripts/cancel-superseded-pr-runs.sh`.
  - [ ] 3.1.1 `select` mode: one `jq -r` program, `--argjson self_id`, rules 0-12 including 9b
    in plan order, `@tsv` output.
  - [ ] 3.1.2 Run mode, env validation: exit 2 on empty env; ignore unknown env variables.
  - [ ] 3.1.3 Run mode, context reads: `PR_CREATED_AT` and `SELF_CREATED_AT`, both validated
    against the ISO regex (exit 2 on mismatch).
  - [ ] 3.1.4 Run mode, listing: 2 unfiltered paginated list calls with `created>=PR date`, `@uri`
    branch encoding, `unique_by(.id)`, a ≥1,000-row truncation warning, and print
    `X-RateLimit-Remaining`.
  - [ ] 3.1.5 Run mode, guard A: **after** listing, up to 3 head reads 5 s apart
    (`CSPR_HEAD_RETRY_SLEEP`); must equal the event head, else exit 0 with no cancels.
  - [ ] 3.1.6 Run mode, cancel: graceful `/cancel` only. Classify the code from the `-i` status
    line and the message from stderr/body (the 202 / 409 / 404 / 429 / 403 split; a 403 is
    `refused` only for dynamic runs). `sanitize()` every API string; read rows with
    `IFS=$'\t' read -r`. `CSPR_DRY_RUN=1` prints `would-cancel` rows and makes no POSTs.
  - [ ] 3.1.7 Run mode, summary: write the summary line to stdout and `$GITHUB_STEP_SUMMARY`,
    and set the exit code.
  - [ ] 3.1.8 `mktemp` plus an owned `trap` for temp files; errexit-safe `if x=$(…)` captures.
- [x] 3.2 Create `.github/workflows/cancel-superseded-pr-runs.yml`.
  - Triggers: `synchronize` and `reopened`.
  - Permissions: `actions: write`, `contents: read`, `pull-requests: read`.
  - Concurrency group per PR, with `cancel-in-progress: true`.
  - Job `if:`: same-repo, not Dependabot (`actor` and `triggering_actor`), and `head.ref` is not
    the default branch.
  - Checkout pinned to `ref: default_branch` with `sparse-checkout: .github/scripts`
    (security P0). A bootstrap `::notice::` exit when the script is absent; never fall back to
    the PR's copy.
  - SHA-pinned checkout; env-only `head.ref`.
  - Header comment carrying the ledger pointer.
- [x] 3.3 Edit `scripts/pr-fanout-ledger.txt`.
  - Add the new row (`1 no yes <consequence>`).
  - Correct the stale "state lock" reasons on the `infra-validation.yml` and
    `apply-sentry-infra.yml` rows, using the exact per-row texts in the plan and keeping
    `no cancel:`.
  - Add a header paragraph about the external reaper.
- [x] 3.4 Add `### Addendum 2026-09-24 — superseded runs are reaped by head SHA, across workflows`
  to ADR-216. Include the rejected alternatives, the named residuals, the corrections to the
  2026-09-14 addendum, the ADR-032 #5585 pointer, the trust boundary and env contract, the
  `always()` jobs on reaped runs, the `fix-constraints-stage-a` safety note, and the
  mutex-release discrepancy.
- [x] 3.5 In `.github/workflows/main-health-monitor.yml`, change the prose "12 fixture suites" to
  "13 fixture suites" (a one-token edit).

## Phase 4: Verification

- [x] 4.1 Run the new suite and `run-all.sh` (green), Guard 1 mutation rows 1-10 (each RED)
  and H7 (GREEN). Record the results for the PR body.
- [x] 4.2 Run `bash plugins/soleur/test/pr-fanout-ledger.test.sh` (green).
- [x] 4.3 Run the lints:
  - `actionlint` on the new workflow
  - `python3 scripts/lint-workflow-step-env-refs.py`
  - `python3 scripts/lint-workflow-errexit-capture.py`
  - `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
  - `python3 scripts/lint-trap-tempfile-ownership.py`
  - `bash scripts/lint-orphan-test-suites.sh`
- [x] 4.4 Run `bash plugins/soleur/test/c4-count-parity.test.sh` (green; this backs "no C4
  impact").
- [x] 4.5 Check AC9: the workflow diff is the new file plus the one-token `main-health-monitor`
  edit, and tenant-integration / vendor-pin-verify are byte-identical.
- [ ] 4.6 AC10 local **dry-run**: push a second commit while the first commit's runs are active,
  then run the script locally with `CSPR_DRY_RUN=1` against #8669. Confirm `would-cancel` rows
  appear only for the old SHA, and paste the summary into the PR body. The in-Actions run shows
  the bootstrap `::notice::`.
- [ ] 4.7 Merge through required checks only (never `--admin`). After merge, run AC12-AC14:
  workflow active, the first real reap, and the CodeQL dynamic and mutex-path observations
  appended to the ADR-216 addendum.
