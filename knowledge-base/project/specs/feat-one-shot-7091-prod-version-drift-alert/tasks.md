---
feature: feat-one-shot-7091-prod-version-drift-alert
issue: 7091
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-01-feat-prod-version-drift-alerter-plan.md
date: 2026-08-01
---

# Tasks — production version-drift alerter (#7091)

Derived from the finalized (post-review, v3) plan. Read the plan's **Design Decisions 1–5** before
starting: the invariant is a `git rev-list` range query, not a SHA equality test, and three separate
review findings are encoded in the workflow's step conditions.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-run the plan's Research Reconciliation validations against live prod; confirm the
      steady-state case still returns `CLEAN`.
- [ ] 0.2 Confirm `jobs.release.with.path_filter` in `.github/workflows/web-platform-release.yml`
      still equals the plan's `PATHSPEC` constant verbatim.
- [ ] 0.3 Confirm the four serial `timeout-minutes` (await-ci 60, migrate 30, verify-migrations 15,
      deploy 90) still sum to 195.
- [ ] 0.4 Confirm `python3 -c "import yaml"` succeeds (Part B extraction depends on PyYAML).
- [ ] 0.5 Read `scripts/inngest-liveness-classify.sh` + `scripts/inngest-liveness-classify.test.sh`
      and `.github/workflows/scheduled-zot-restart-loop.yml` as the canonical triple to mirror.
- [ ] 0.6 Confirm `ci/prod-version-drift` does **not** yet exist as a label (it must be bootstrapped
      by the workflow, not created by hand).

## Phase 1 — RED: tests first (`cq-write-failing-tests-before`)

- [ ] 1.1 Create `scripts/prod-version-drift-check.test.sh` with the harness conventions from
      `scripts/lint-workflow-step-env-refs.test.sh`: `set -uo pipefail` (no `-e`), `PASS`/`FAIL`
      counters, `mktemp -d` + `trap … EXIT`, exit 1 on any failure **or** on assertion-count
      regression below `MIN_ASSERTIONS`.
- [ ] 1.2 Write Part A fixtures A1–A17 (see plan's Test Strategy table). Assert on **exit codes**.
      Include A5 (`skip_deploy`), A6 (non-resetting clock), A7 (multi-commit push), A16/A17
      (`build_sha`-vs-`version` disagreeing cells).
- [ ] 1.3 Write Part B wiring pins B1–B10 using PyYAML extraction from the shipped workflow, with an
      **exactly-one cardinality assertion** on every step-id selector.
- [ ] 1.4 Write Part C mutation axes 1–10. Each must assert the mutation **landed** before scoring,
      and the unmutated control must run first and be green.
- [ ] 1.5 Confirm the suite fails because the checker is absent — not vacuously.

## Phase 2 — GREEN: the checker

- [ ] 2.1 Create `scripts/prod-version-drift-check.sh` with documented constants `PATHSPEC` and
      `DRIFT_SUSTAINED_THRESHOLD_MIN=195`.
- [ ] 2.2 Implement pure `classify_drift()` — inputs `(prod_json, curl_rc, missing_count,
      oldest_epoch, revlist_rc, now_epoch)`, outputs verdict + reason + exit code. No network, no git.
- [ ] 2.3 Implement `main()` I/O only: curl `/health` with `--max-time` and **3× backoff retry**;
      then `git rev-list --first-parent --format='%H %ct' "$prod_sha..origin/main" -- $PATHSPEC`.
      **Capture `rc` directly from git/curl — never through a pipe** (see plan Sharp Edges).
- [ ] 2.4 Validate `build_sha` to 40-hex, rejecting the literal string `null`, empty, and non-JSON.
- [ ] 2.5 Emit `DRIFT_VERDICT=`, `DRIFT_REASON=`, `DRIFT_DETAIL=`, `DRIFT_MISSING_COUNT=` lines.
- [ ] 2.6 Header comment documenting the `skip_deploy` true-positive case and the `--first-parent`
      rationale.
- [ ] 2.7 Run the suite to green.

## Phase 3 — The workflow

- [ ] 3.1 Create `.github/workflows/scheduled-prod-version-drift.yml` with
      `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->` on **line 1** plus the
      Decision-4 justification header.
- [ ] 3.2 `on: schedule: */30 * * * *` + bare `workflow_dispatch: {}`.
- [ ] 3.3 `permissions: {contents: read, issues: write}`;
      `concurrency: {group: scheduled-prod-version-drift, cancel-in-progress: false}`;
      `runs-on: ubuntu-24.04`; `timeout-minutes: 10`.
- [ ] 3.4 SHA-pinned `actions/checkout` with **`fetch-depth: 0`**.
- [ ] 3.5 Checker step (`id: check`): capture exit code as **data** into `$GITHUB_OUTPUT`; never let
      it fail the step; `strip_log_injection` before any `::error::` interpolation.
- [ ] 3.6 Label bootstrap: `gh label create "ci/prod-version-drift" … 2>/dev/null || true`
      **before** any `gh issue create`.
- [ ] 3.7 Drift steps gated `!cancelled() && steps.check.outputs.exit_code == '1'` — issue
      create-or-comment (dedupe by title search), emitting `first_detection`; email
      (`id: notify`, emitting `delivered`) additionally gated on `first_detection == 'true'`.
- [ ] 3.8 Check-error steps gated `!cancelled() && steps.check.outputs.exit_code == '2'` — separate
      issue class + email.
- [ ] 3.9 Close-on-recovery step gated `!cancelled() && steps.check.outputs.exit_code == '0'` —
      find the open tracking issue and `gh issue close` with a recovery comment.
- [ ] 3.10 Terminal `sentry-heartbeat` step, `if: always()`, `continue-on-error: true`,
      `monitor-slug: scheduled-prod-version-drift`, with the Decision-5 `status:` expression
      (first conjunct `steps.check.outcome == 'success'`; drift arm requires `delivered == '1'`).
- [ ] 3.11 Run the suite; Part B must now pass.

## Phase 4 — Terraform monitor

- [ ] 4.1 Add `resource "sentry_cron_monitor" "scheduled_prod_version_drift"` to
      `apps/web-platform/infra/sentry/cron-monitors.tf` — `crontab = "*/30 * * * *"`,
      `checkin_margin_minutes = 30`, `max_runtime_minutes = 10`, `failure_issue_threshold = 1`,
      `recovery_threshold = 1`, `timezone = "UTC"`.
- [ ] 4.2 Header comment citing the `margin == interval` jitter-tolerance rationale and noting the
      superseded 480 figure.
- [ ] 4.3 Confirm the slug matches the workflow's `monitor-slug`;
      `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` passes.

## Phase 5 — Register, C4, cross-references

- [ ] 5.1 Register the suite in `scripts/test-all.sh`:
      `run_suite "scripts/prod-version-drift-check" bash scripts/prod-version-drift-check.test.sh`.
- [ ] 5.2 `bash scripts/lint-orphan-test-suites.sh` exits 0.
- [ ] 5.3 `model.c4` edit 1 — `github -> sentry` counts (6→7 workflows, 3→4 GHA-schedule-fired,
      51→52 monitors, 7→8 checking in from CI).
- [ ] 5.4 `model.c4` edit 2 — `github -> resend` "nine Resend emitters" → ten.
- [ ] 5.5 `model.c4` edit 3 — new `github -> webapp` edge for the version-drift probe, distinct from
      the existing ADR-074 Stage-B edge.
- [ ] 5.6 `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] 5.7 Two forward-pointer comments in `.github/workflows/web-platform-release.yml` at
      `with.path_filter` and `deploy.timeout-minutes` naming the parity assertions. Comments only.

## Phase 6 — Exit gate

- [ ] 6.1 `bash scripts/test-all.sh scripts` exits 0 (the gate's own invocation).
- [ ] 6.2 `python3 scripts/lint-workflow-step-env-refs.py` exits 0.
- [ ] 6.3 `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0.
- [ ] 6.4 `actionlint` clean on the new workflow; `bash -n` on each extracted `run:` body.
- [ ] 6.5 Walk the plan's Pre-merge Acceptance Criteria 1–18 and record evidence for each.

## Phase 7 — Post-merge (automated via `/ship`; no operator step)

- [ ] 7.1 `gh workflow run scheduled-prod-version-drift.yml`; confirm `conclusion: success` and a
      `DRIFT_VERDICT=` line in the run log.
- [ ] 7.2 Confirm via Sentry API read that the monitor exists **and received a check-in** (not just
      that the resource exists).
- [ ] 7.3 Exercise the alert path end-to-end with an injected old SHA: confirm label created, issue
      filed, email delivered — then confirm the next clean run closes the issue.
- [ ] 7.4 File the three Deferred Items as issues (release-job timeout; #7142 re-page;
      C4 count parity).
- [ ] 7.5 `gh issue close 7091`.
