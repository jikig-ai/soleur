---
title: "TR9 PR-3 — migrate scheduled-oauth-probe + scheduled-github-app-drift-guard to Inngest cron substrate"
issue: 4211
parent_umbrella: 3948
precedents: [3985, 4062]
prior_plan: knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md
prior_immediate_relief: 4207
brand_survival_threshold: single-user incident
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-21-tr9-pr3-oauth-probe-drift-guard-inngest-brainstorm.md
---

# Feature: TR9 PR-3 — OAuth-probe + GitHub-App drift-guard → Inngest cron

## Problem Statement

Both `scheduled-oauth-probe` and `scheduled-github-app-drift-guard` run on GitHub Actions hourly cron, which has degraded to ~150-min median / 293-min max gaps under runner-pool load (49 fires, 2026-05-18..21 window). PR #4207 silenced the resulting recurring Sentry missed-checkin alerts by bumping `checkin_margin_minutes` from 30 → 360 (oauth-probe) and 180 → 360 (drift-guard), but this makes both monitors decorative for outages shorter than ~6h. Real auth-flow regressions still page via the workflow's Resend ops-email + `[ci/auth-broken]` GitHub issue paths, but the canary's missed-checkin signal is now unusable. The structural fix is to migrate both probes onto the self-hosted Inngest cron substrate (Hetzner VM), matching TR9 PR-1 (#3985) and PR-2 (#4062) precedent — where Inngest fires deterministically (≤2-min jitter) and 30-min margins are honest. PR #3985 + PR #4062 are both running cleanly in production today (2026-05-21 04:00 + 09:00 UTC checkins verified via Sentry API).

## Goals

- Both hourly probes run on the self-hosted Inngest cron substrate, firing within 2 min of schedule.
- Both Sentry monitors restored to `checkin_margin_minutes = 30` + `failure_issue_threshold = 1` (honest signal under tight margins).
- Both `.github/workflows/scheduled-*.yml` files deleted in the same commit the Inngest functions land (TR9 I-13 — no parallel firing).
- The detection contract is preserved end-to-end: a real OAuth or GitHub-App auth regression must surface as `?status=error` heartbeat + `[ci/auth-broken]` issue within the same SLO as today, validated post-merge against canonical failure sentinels.
- Operator runbooks updated for the new operator surfaces (Inngest dashboard / `inngest send cron/<fn>.manual-trigger`).

## Non-Goals

- No new sub-processor inventory (Inngest is already Article-30 PA 13, PR-F #3244).
- No DPA addendum / LIA / compliance-posture row (CLO carry-forward verdict).
- No new ADR (inherits ADR-030 + ADR-033 from the substrate).
- No two-step `in_progress → ok/error` Sentry heartbeat pattern (banned by 2026-05-18 vendor-cron-heartbeat-silent-fail learning).
- No shadow-fire dual-substrate overlap (would double check-ins to the same monitor slug and mutually mask failures).
- No `send-ops-notification.ts` helper extraction (single new consumer; YAGNI).
- No migration of `scheduled-cf-token-expiry-check` or sibling-but-distinct monitors (out of scope; tracked separately).

## Functional Requirements

### FR1: `cron-oauth-probe` Inngest function ports the bash probe contract

A new `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` function:
- Cron: `0 * * * *` (hourly, matching the existing GHA workflow's cadence)
- Manual-trigger event: `cron/oauth-probe.manual-trigger` (operator convention from PR-1/PR-2)
- Implements all 8 canonical failure-body sentinels from `.github/workflows/scheduled-oauth-probe.yml` (the 540-line bash probe), verified against the load-bearing strings catalogued by `apps/web-platform/test/oauth-probe-contract.test.ts`
- Files a `[ci/auth-broken]` GitHub issue and sends a Resend ops-email on any failure mode
- Posts a single end-of-job Sentry heartbeat per the established `cron-daily-triage.ts:329-371` shape (NO two-step pattern)

### FR2: `cron-github-app-drift-guard` Inngest function ports the drift-guard contract

A new `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` function, same architectural shape as FR1 but on the drift-guard probe surface. Reuses the existing `.github/actions/sentry-heartbeat/action.yml` composite's status-branch logic for the divergent failure_mode handling.

### FR3: Sentinel module extracted within-PR

A new `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` module holds the load-bearing failure-body strings (`redirect_uri is not associated`, `Application suspended`, `authenticity_token` regex). BOTH the new Inngest function AND the existing `apps/web-platform/test/oauth-probe-contract.test.ts` import from it; the test's pre-existing duplicate string literals are removed in the same commit (single source of truth, no consumer-drift window).

### FR4: Sentry monitors tightened back to honest margins

`apps/web-platform/infra/sentry/cron-monitors.tf` reverts both monitors to `checkin_margin_minutes = 30` and `failure_issue_threshold = 1`. The May 21 immediate-relief comment block (lines 71-77 of the resource) is replaced with the original "all monitors deterministic" narrative.

### FR5: Workflow deletion in the same commit

Both `.github/workflows/scheduled-oauth-probe.yml` and `.github/workflows/scheduled-github-app-drift-guard.yml` are deleted in the same commit the Inngest functions land. No parallel firing (TR9 I-13 precedent).

### FR6: Runbook updates

`knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` and `github-app-drift.md` updated to reference the new operator surfaces:
- Inngest dashboard URL for live function state
- `inngest send cron/<fn>.manual-trigger` for operator-initiated re-probe
- `oauth-probe-contract.test.ts` sentinel module as the contract source

## Technical Requirements

### TR1: Inngest function shape inherits TR9 precedent verbatim

Both new functions MUST mirror the PR-1/PR-2 invariant set:
- `concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` — the literal `'"cron-platform"'` is load-bearing per the F7 Architecture invariant; prevents cron-* fan-out OOM.
- `retries: 1` — established cron-* default; probes are idempotent (GET-only HTTP checks).
- Single end-of-job Sentry heartbeat via `step.run("sentry-heartbeat", ...)` per `cron-daily-triage.ts:329-371`.
- Registered in `apps/web-platform/app/api/inngest/route.ts:37` alongside existing siblings.

### TR2: Heartbeat shape uses validated single-step pattern only

NO two-step `in_progress → ok/error` heartbeat (banned by `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`). One `if: always()`-equivalent POST at end-of-job. `max_runtime_minutes` in the Sentry monitor stays decorative.

### TR3: Post-merge detection contract (AC26)

Post-merge, fire `inngest send cron/oauth-probe.manual-trigger` (and the drift-guard equivalent) with a `data.overrideHost` pointing at a fixture URL serving each of the 8 canonical failure-body sentinels. Assert each maps to the correct `failureMode` AND a `?status=error` heartbeat lands in Sentry's checkins API within 90s per mode. If the handler doesn't support a host-override input, narrow the AC to "one synthetic failure mode via a feature-flagged probe target." This validates the canary still squawks, not just that it ticks.

### TR4: Pre-deletion staging gate (AC27)

The `.github/workflows/scheduled-{oauth-probe,github-app-drift-guard}.yml` deletion is staged ONLY after `inngest send cron/oauth-probe.manual-trigger` lands successfully in **staging** Inngest. Collapses the up-to-90-min cutover-blindness window if `app/api/inngest/route.ts:37` silently fails to discover the new function (typo, dead-code elimination, registration drift).

### TR5: Substrate-vs-probe disambiguation in issue template (AC28)

The `[ci/auth-broken]` issue template (filed in-process by `cron-oauth-probe.ts` on probe failure) MUST include the last Better Stack heartbeat timestamp inline. Source: pull from `https://uptime.betterstack.com/api/v2/heartbeats` for the `inngest-heartbeat` monitor at issue-file time. Operator opening the issue sees substrate-vs-probe disambiguation without dashboard hopping. Closes #4116-class silent-substrate-fail residual risk.

### TR6: Reuse existing sentry-heartbeat composite action

`.github/actions/sentry-heartbeat/action.yml` is the shared 5-input composite covering both probe-status branches (drift-guard's divergent `failure_mode == '' && tripwire.outcome != 'failure'` is already wired). The Inngest function calls the same Sentry checkins API directly; do NOT inline a 9th copy of the heartbeat shape. (Source: `2026-05-18-composite-action-extraction-inline-on-multi-file-rollout.md`.)

### TR7: Pre-merge six-question self-check (#4116 cascade)

Before declaring the function live, run the six self-check questions from `2026-05-19-inngest-substrate-five-bug-cascade.md`:
1. Does `PUBLIC_PATHS` include `/api/inngest`?
2. Is the `INNGEST_SIGNING_KEY` prefix correct for the environment (`signkey-prod-*` for prd)?
3. Does `User=` match the file owner on the Inngest server (no chown drift)?
4. Does the systemd unit's `ReadWritePaths` cover the SQLite db path?
5. Is the env source-of-truth Doppler (not a leftover `.env` file)?
6. Is the Better Stack `inngest-heartbeat` monitor unpaused before declaring GREEN?

### TR8: Verify infra-validation pathspec matched

Confirm the `apply-sentry-infra.yml` workflow actually ran on this PR's diff before relying on green status (PR-1 #3985, PR-G #4002, and PR-G2 #4003 all had `validate: SKIPPED` due to `git diff -- 'apps/*/infra/'` zero-matching). Source: `2026-05-18-infra-validation-pathspec-silent-zero-match.md`.

### TR9: Article-30 / GDPR-gate state

No new sub-processor. No new processing activity. No new DPA. Article-30 register PA 13 (self-hosted Inngest, PR-F #3244) already covers the substrate. GDPR-gate non-triggered (CLO confirmed). `requires_cpo_signoff: true` (flipped from the prior plan's `false` due to brand-survival threshold elevation).

## Acceptance Criteria

The plan's existing 25 ACs (AC1–AC25 per `knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md`) are inherited verbatim, with the following named scope additions:

- **AC26:** Post-merge detection contract (per TR3).
- **AC27:** Pre-deletion staging gate (per TR4).
- **AC28:** Substrate-vs-probe disambiguation in `[ci/auth-broken]` issue body (per TR5).

The plan's `requires_cpo_signoff` MUST flip from `false` to `true` at /work-time given the threshold elevation.

## Domain Review (carry-forward)

| Domain | Verdict | Source |
|---|---|---|
| Product (CPO) | Threshold elevation holds; AC26 added | Phase 0.5 focused-refresh |
| Engineering (CTO) | AC27 + AC28 added; same-commit deletion safe per AC9 rationale; sentinel-module extraction within-PR | Phase 0.5 focused-refresh |
| Legal (CLO) | Carry-forward only; Article-30 PA 13 covers Inngest | Phase 0.5 focused-refresh |
