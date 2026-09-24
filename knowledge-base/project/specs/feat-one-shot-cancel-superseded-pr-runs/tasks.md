# Tasks: cancel superseded PR runs

Plan: `knowledge-base/project/plans/2026-09-24-ci-cancel-superseded-pr-runs-plan.md`
(PR #8669; never `--admin` merge: UNTRUSTED-CI).

## Phase 1: Setup

- [ ] 1.1 Re-verify the live API shapes the plan depends on. Check the run object fields
  (`id`, `event`, `head_branch`, `head_sha`, `created_at`, `status`, `path`,
  `head_repository.full_name`) for pull_request, pull_request_target and dynamic runs. Check the
  `gh api -i` status-line format on a no-op 409 cancel against a completed run.
- [ ] 1.2 Read `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` (the gh-stub pattern) and
  `.github/scripts/test/run-all.sh` (the contract and the `MIN_SUITES` floor).

## Phase 2: Tests first (RED)

- [ ] 2.1 Create `.github/scripts/test/test-cancel-superseded-pr-runs.sh`, bash-only with an
  assertion floor.
  - [ ] 2.1.1 Selection layer: rows S0a-S13, covering both sides of every rule.
  - [ ] 2.1.2 Orchestration layer: stubbed `gh` with a per-call head sequence, rows O1-O15
    (including A→B→A, head moved during listing, no `status=`, no `force-cancel`).
  - [ ] 2.1.3 Confirm the suite is RED against a missing script.
- [ ] 2.2 Bump `MIN_SUITES` 12 → 13 in `.github/scripts/test/run-all.sh`, with a provenance
  sentence.

## Phase 3: Core implementation (GREEN)

- [ ] 3.1 Create `.github/scripts/cancel-superseded-pr-runs.sh`.
  - [ ] 3.1.1 `select` mode: one `jq -r` program, `--argjson self_id`, rules 0-12 in plan
    order, `@tsv` output.
  - [ ] 3.1.2 Run mode, env validation: exit 2 on empty env.
  - [ ] 3.1.3 Run mode, guard A: 3 head reads 5 s apart, with the sleep injectable via
    `CSPR_HEAD_RETRY_SLEEP`.
  - [ ] 3.1.4 Run mode: validate `SELF_CREATED_AT` against the ISO regex.
  - [ ] 3.1.5 Run mode, listing: 2 unfiltered paginated list calls, `@uri` branch encoding,
    `unique_by(.id)`, print `X-RateLimit-Remaining`.
  - [ ] 3.1.6 Run mode: re-read the head before the cancel loop.
  - [ ] 3.1.7 Run mode, cancel: graceful `/cancel` only, classified by the `-i` status line
    (202 / 409 / 404 / 429 / 403 split), with CR/LF-stripped annotations.
  - [ ] 3.1.8 Run mode, summary: write the summary line to stdout and `$GITHUB_STEP_SUMMARY`,
    and set the exit code.
  - [ ] 3.1.9 `mktemp` plus an owned `trap` for temp files; errexit-safe `if x=$(…)` captures.
- [ ] 3.2 Create `.github/workflows/cancel-superseded-pr-runs.yml`.
  - Triggers: `synchronize` and `reopened`.
  - Permissions: `actions: write`, `contents: read`, `pull-requests: read`.
  - Concurrency group per PR, with `cancel-in-progress: true`.
  - Job `if:`: same-repo and not Dependabot.
  - SHA-pinned checkout; env-only `head.ref`.
  - Header comment carrying the ledger pointer.
- [ ] 3.3 Edit `scripts/pr-fanout-ledger.txt`.
  - Add the new row (`1 no yes <consequence>`).
  - Correct the stale "state lock" reasons on the `infra-validation.yml` and
    `apply-sentry-infra.yml` rows, keeping `no cancel:`.
  - Add a header paragraph about the external reaper.
- [ ] 3.4 Add `### Addendum 2026-09-24 — superseded runs are reaped by head SHA, across workflows`
  to ADR-216. Include the rejected alternatives, the named residuals, and the mutex-release
  discrepancy.

## Phase 4: Verification

- [ ] 4.1 Run the new suite and `run-all.sh` (green), plus harness rows H1-H7 and Guard 1
  mutation rows 1-8. Record the results for the PR body.
- [ ] 4.2 Run `bash plugins/soleur/test/pr-fanout-ledger.test.sh` (green).
- [ ] 4.3 Run the lints:
  - `actionlint` on the new workflow
  - `python3 scripts/lint-workflow-step-env-refs.py`
  - `python3 scripts/lint-workflow-errexit-capture.py`
  - `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
  - `python3 scripts/lint-trap-tempfile-ownership.py`
  - `bash scripts/lint-orphan-test-suites.sh`
- [ ] 4.4 Run `bash plugins/soleur/test/c4-count-parity.test.sh` (green; this backs "no C4
  impact").
- [ ] 4.5 Check AC9: the diff under `.github/workflows/` is only the new file.
- [ ] 4.6 AC10 live: push a second commit while the first commit's runs are active. Confirm the
  reaper log shows `cancelled>=1`, no head-SHA run is cancelled, and record the CodeQL dynamic
  result. Paste the summary into the PR body.
- [ ] 4.7 Merge through required checks only (never `--admin`). After merge, run AC12 and AC13.
