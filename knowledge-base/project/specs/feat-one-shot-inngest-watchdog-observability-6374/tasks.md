---
plan: knowledge-base/project/plans/2026-07-13-fix-inngest-watchdog-observability-defects-plan.md
branch: feat-one-shot-inngest-watchdog-observability-6374
lane: cross-domain
---

# Tasks — Inngest health-watchdog observability defects

## Phase 0 — Preconditions & premise verification
- [ ] 0.1 Confirm no live `scheduled-inngest-health` Sentry monitor exists (grep already shows absence; verify live via monitor list if a token is available — idempotent regardless).
- [ ] 0.2 Read the two most-recent `sentry_cron_monitor` blocks in `cron-monitors.tf`; adopt field conventions (schedule shape, margin/runtime/threshold, timezone).
- [ ] 0.3 Confirm `apply-sentry-infra.yml` path filter includes `cron-monitors.tf` (auto-apply, no operator step).
- [ ] 0.4 Read `hooks.json.tmpl` + `inngest-registry-probe.sh` + infra-config payload wiring to mirror the hook-delivery pattern.
- [ ] 0.5 Gather inngest-liveness evidence around 2026-07-12 20:43Z (Sentry `scheduled-inngest-cron-watchdog` check-ins / function fires) → record #6374 false-positive verdict.

## Phase 1 — Defect 1: delivery gap (page the operator)
- [ ] 1.1 Add `sentry_cron_monitor "scheduled_inngest_health"` (name `scheduled-inngest-health`, `*/15` crontab, margin/runtime/threshold per 0.2, threshold=1) to `cron-monitors.tf`.
- [ ] 1.2 Write GHA-workflow-heartbeat-slug ↔ monitor parity test (counterpart to `sentry-monitor-iac-parity.test.ts`); verify red on a broken fixture, green on the tree. Confirm runner/path against `vitest.config.ts` globs.
- [ ] 1.3 Confirm cron-monitor failure pages the operator; if insufficient, add belt-and-suspenders tagged-event `sentry_issue_alert` (decide in deepen-plan).

## Phase 2 — Defect 2: true liveness probe
- [ ] 2.1 Create `apps/web-platform/infra/inngest-health.sh` — curl `127.0.0.1:8288/health` (+ lightweight `/v0/gql functions`); emit pure JSON `{healthy, functions_count, durability_state}`; enum/count only; journald-only markers.
- [ ] 2.2 Create `apps/web-platform/infra/inngest-health.test.sh` fixtures (healthy / process-down / api-degraded; assert eventsV2 is NOT on the liveness path).
- [ ] 2.3 Register `/hooks/inngest-health` in `hooks.json.tmpl` + wire `inngest_health_sh_b64` through infra-config-apply (+ `.test.sh`) and infra-config-install.
- [ ] 2.4 Repoint `scheduled-inngest-health.yml` liveness probe from `/hooks/inngest-inventory` to `/hooks/inngest-health`; keep 3× retry; move durability read to the health hook (or keep both per deepen-plan).

## Phase 3 — Defect 3: restart cap + escalate
- [ ] 3.1 Add restart-dispatch counter persisted on the `[ci/inngest-down]` issue (`<!-- restart-dispatch-count: N -->` marker or comment count).
- [ ] 3.2 Gate the auto-dispatch step on `N < RESTART_CAP`; at the cap, suppress dispatch + escalate (loud comment + human-attention label). Unit-test the counter + cap branch (no LLM/network in the assertion path).
- [ ] 3.3 Confirm pool modes stay excluded from the restart gate (unchanged).

## Phase 4 — Readiness-gate inngest awareness
- [ ] 4.1 Decide insertion surface (postmerge prod-health / go preamble / one-shot Step 0) in deepen-plan; add `gh issue list --label ci/inngest-down --state open` advisory (+ optional `/hooks/inngest-health` probe). Advisory, never hard-block.
- [ ] 4.2 If in `commands/go.md`, keep the addition OUTSIDE the eval-gated routing block.

## Phase 5 — Tracking & #6374 disposition
- [ ] 5.1 PR body: `Ref #6374` (NOT `Closes`).
- [ ] 5.2 Post-merge: confirm monitor applied + `/hooks/inngest-health` live; close #6374 with the Phase-0 verdict.

## Verification (exit gate)
- [ ] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] Shell tests (`.test.sh`) + vitest for new `.ts` parity test green.
- [ ] All Pre-merge Acceptance Criteria in the plan satisfied.
