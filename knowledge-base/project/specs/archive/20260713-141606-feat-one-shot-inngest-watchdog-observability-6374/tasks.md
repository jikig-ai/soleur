---
plan: knowledge-base/project/plans/2026-07-13-fix-inngest-watchdog-observability-defects-plan.md
branch: feat-one-shot-inngest-watchdog-observability-6374
lane: cross-domain
---

# Tasks — Inngest health-watchdog observability defects

## Phase 0 — Preconditions & premise verification
- [x] 0.1 Confirm no live `scheduled-inngest-health` Sentry monitor exists (grep already shows absence; verify live via monitor list if a token is available — idempotent regardless).
- [x] 0.2 Read the two most-recent `sentry_cron_monitor` blocks in `cron-monitors.tf`; adopt field conventions (schedule shape, margin/runtime/threshold, timezone).
- [x] 0.3 Confirm `apply-sentry-infra.yml` path filter includes `cron-monitors.tf` (auto-apply, no operator step).
- [x] 0.4 Read `hooks.json.tmpl` + `inngest-registry-probe.sh` + infra-config payload wiring to mirror the hook-delivery pattern.
- [x] 0.5 Gather inngest-liveness evidence around 2026-07-12 20:43Z (Sentry `scheduled-inngest-cron-watchdog` check-ins / function fires) → record #6374 false-positive verdict.

## Phase 1 — Defect 1: delivery gap (page the operator)
- [x] 1.1 Add `sentry_cron_monitor "scheduled_inngest_health"` (name `scheduled-inngest-health`, `*/15` crontab, margin/runtime/threshold per 0.2, threshold=1) to `cron-monitors.tf`.
- [x] 1.2 **[BLOCKER] Add `-target=sentry_cron_monitor.scheduled_inngest_health` to `.github/workflows/apply-sentry-infra.yml`** (`:219` cohort) — without it the monitor is declared but never applied (saved-plan `-target=` allowlist, not untargeted).
- [x] 1.3 Extend `sentry-monitor-iac-parity.test.ts` to assert workflow heartbeat slugs have BOTH a `sentry_cron_monitor.name` AND an `apply-sentry-infra.yml` `-target=` entry; red on a broken fixture per clause. (Fold in — do not create a new file.)
- [x] 1.4 Pull pre-merge live evidence a sibling cron-monitor failure notified `ops@jikigai.com` (Sentry monitor-notification history). If unobtainable, add the `sentry_issue_alert` fallback. Default: monitor-only (paging documented at `cloud-scheduled-tasks.md:476-480`).

## Phase 2 — Defect 2: true liveness probe (DEFAULT = Option A, reuse inventory)
- [x] 2.1 **Option A (default):** add `INVENTORY_LIVENESS_ONLY` mode to `inngest-inventory.sh` — skip the eventsV2 scan (emit `event_names:[]`, `armed_reminders:[]`), keep the `/v0/gql functions` query + `durability_state`; return `{functions,functions_count,durability_state}`. Optionally add a `127.0.0.1:8288/health` line. (Option B alt: new `inngest-health.sh` + `/hooks/inngest-health` + push-infra-config payload + infra-config-apply FILE_MAP + vector.toml allowlist + vector drift fixture.)
- [x] 2.2 Extend `inngest-inventory.test.sh` (Option A) with liveness-only + durability + probe-unavailable fixtures; assert eventsV2 is NOT called in liveness mode.
- [x] 2.3 Wire the probe: `hooks.json.tmpl` — Option A adds a small `inngest-liveness` hook running the already-staged `inngest-inventory.sh` with the env flag (reuse `INNGEST_INVENTORY_SH_B64`, no new payload).
- [x] 2.4 Repoint `scheduled-inngest-health.yml` liveness to the liveness-only probe; keep 3× retry. **Deploy-race tolerance:** 404/000/non-well-formed → `probe_unavailable` (NO restart); only a well-formed `healthy:false`/missing-`.functions` → `inngest_down`. functions_count==0 → grace/retry before `inngest_unhealthy`.
- [x] 2.5 **Preserve durability wiring:** `steps.probe.outputs.durability_state` still resolves; `degraded` fixture opens `[ci/inngest-degraded-durability]` (`:414`), `durable` fixture auto-closes it (`:460`).

## Phase 3 — Defect 3: restart give-up (issue-AGE gate, NOT a counter)
- [x] 3.1 Insert a count-free gate step BEFORE the dispatch step: read the open `[ci/inngest-down]` issue `createdAt`; emit `restart_ok` (absent→true / age<GIVE_UP_WINDOW≈45min→true / age≥window→false).
- [x] 3.2 Gate the dispatch `if:` on `restart_ok=='true'` + the down-family predicate. At give-up: the file-issue down-branch REPLACES its "Restart re-dispatched" comment (`:371`) with a loud "restarts exhausted" comment (thread `restart_ok` as output for truthful text) + human-attention label (escalate once at the boundary).
- [x] 3.3 Paging continues at give-up (heartbeat keys off `failure_mode`, not dispatch). Reset is self-correcting via auto-close (no marker reset needed).
- [x] 3.4 Document `inngest-watchdog-restart-dispatch.yml:49` (D1-B label path) as out-of-churn-scope. Note Phase 3 effectiveness is contingent on Phase 2's stable probe.
- [x] 3.5 Confirm pool modes stay excluded from the restart gate (unchanged, `:275-278`).

## Phase 3.6 — ADR amendments
- [x] 3.6 Add amendment-log entries to `ADR-031-sentry-as-iac.md` (parity guard) and `ADR-030-inngest-as-durable-trigger-layer.md` (liveness rides `/health`). Cite by filename slug.

## Phase 4 — Readiness-gate inngest awareness
- [x] 4.1 Decide insertion surface (postmerge prod-health / go preamble / one-shot Step 0) in deepen-plan; add `gh issue list --label ci/inngest-down --state open` advisory (+ optional `/hooks/inngest-health` probe). Advisory, never hard-block.
- [x] 4.2 If in `commands/go.md`, keep the addition OUTSIDE the eval-gated routing block.

## Phase 5 — Tracking & #6374 disposition
- [x] 5.1 PR body: `Ref #6374` (NOT `Closes`).
- [x] 5.2 Post-merge: confirm monitor applied + `/hooks/inngest-health` live; close #6374 with the Phase-0 verdict.

## Verification (exit gate)
- [x] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] Shell tests (`.test.sh`) + vitest for new `.ts` parity test green.
- [x] All Pre-merge Acceptance Criteria in the plan satisfied.
