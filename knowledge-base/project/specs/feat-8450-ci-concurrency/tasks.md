# Tasks: CI Actions concurrency ceiling (#8450)

**Plan:** `knowledge-base/project/plans/2026-09-21-ci-actions-concurrency-ceiling-plan.md`
**Issue:** #8450 (linkage: `Ref #8450` — NOT `Closes`; issue resolves post-upgrade verification)
**PR:** #8472 (draft)

## Phase A — Ledger + operator handoff (docs only)

- [x] A.1 Add `approved-not-billing` GitHub Team row to `knowledge-base/operations/expenses.md` (per plan A.1 — note annual-prepay ~$3.67 billing-cycle assumption)
- [x] A.2 Write `knowledge-base/project/specs/feat-8450-ci-concurrency/operator-upgrade-steps.md` (FR4 steps, `gh api orgs/jikig-ai --jq .plan.name` verification, ledger flip, B.5 dispatch step, followthrough-directive posting step); post `action-required` comment on #8450
- [x] A.3 Record pre-change baseline in `measurements.md` (queued-age sample + deploy-arm wait, per-job timestamps, sampling commands, event mix)

## Phase B — Cron cadence trims

- [x] B.1 `scheduled-prod-version-drift.yml` `*/30`→hourly + FR2 comment; paired `sentry_cron_monitor.scheduled_prod_version_drift` crontab edit
- [x] B.2 `scheduled-zot-restart-loop.yml` `*/30`→hourly + FR2 comment + fix `:43-46` margin citation; paired monitor crontab + margin 30→120; rewrite `cron-monitors.tf` ~:1051-1054 and ~:1152-1153 stale rationale
- [x] B.3 `apply-inngest-rls.yml` hourly→`17 */4` + header `:12-18` rewrite; `cron-monitors.tf` ~:1180 advisor-scan comment states real bound
- [x] B.4 Confirm `scheduled-inngest-health.yml` untouched at `*/15`
- [x] B.5 Note expected transient zot missed-check-in + `gh workflow run apply-sentry-infra.yml` dispatch step in `operator-upgrade-steps.md`

## Phase C — `e2e` path gate (in-job classifier, two pushes)

- [x] C.0 RED: write `plugins/soleur/test/ci-e2e-skip-anchors.test.sh` per Guard 1 matrix — must fail before the classifier exists
- [x] C.1 Commit 1 (push alone): `scripts/ci-e2e-classify.sh` + `e2e` classify step (`fetch-depth: 0`) + `::notice::` report — no gating; allowlist = `knowledge-base/**` + root `*.md` only (NOT `docs/**`)
- [ ] C.1a Observation gate: verify this PR's CI reports `applicable=true`; a `false` blocks the flip
- [ ] C.2 Commit 2 (separate push): heavy steps `if: steps.detect.outputs.applicable == 'true'` + skip-verdict step (`::notice::` + `$GITHUB_STEP_SUMMARY`)
- [x] C.3 Anchor audit: enumerate app-affecting trees; record accepted gap set in `measurements.md`
- [x] C.4 `scripts/pr-fanout-ledger.txt` — `consequence` text only; `paths` flag stays `no`
- [x] C.5 Verify `scripts/required-checks.txt` + canonical JSON unchanged; parity test green
- [x] C.6 ADR-032 amendment recording the shared-job gate variant + slot-hold residual (D.3a)

## Phase D — Probe + verification wiring

- [x] D.0 RED: `scripts/followthroughs/actions-queue-tail-8450.test.sh` Guard 2 fixture matrix — must fail before probe exists
- [x] D.1 Write `scripts/followthroughs/actions-queue-tail-8450.sh` (run-level `created_at→run_started_at`, `--event workflow_run` filter, `plan.name` precondition → SKIP-DECLARED, `UPGRADE_NOT_BEFORE` cutoff, ≥5 runs / p95<15min); pin `job.created_at` semantics empirically first
- [x] D.1b Add `actions: read` to `scheduled-followthrough-sweeper.yml` job permissions
- [ ] D.3b (post-upgrade, separate commit) ADR-032 reopener-(iii) flip
- [ ] D.4 Re-evaluation note on #8450

## Verification + ship

- [x] V.1 `actionlint` clean on every edited workflow; `bash -n` on new scripts
- [x] V.2 `pr-fanout-ledger.test.sh`, `required-checks-canonical-parity.test.sh`, `workflow-file-size.test.ts` green
- [ ] V.3 `gh api orgs/jikig-ai --jq .plan.name` (AC-TEAM, post-operator-upgrade)
- [ ] V.4 AC-TAIL soak via probe; numbers recorded in `measurements.md`
- [ ] V.5 Commit + push; PR body `Ref #8450`; GDPR gate re-run at work Phase 2 exit
