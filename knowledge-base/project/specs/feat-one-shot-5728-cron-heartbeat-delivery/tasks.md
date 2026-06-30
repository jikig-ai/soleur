---
feature: feat-one-shot-5728-cron-heartbeat-delivery
issue: 5728
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-29-fix-cron-heartbeat-delivery-timing-plan.md
---

# Tasks — fix #5728 cron heartbeat delivery/timing defect

Derived from the plan. **Phase 0 is a hard gate** — its verdict decides which later phase is
load-bearing vs. defense-in-depth. **Do NOT introduce an `in_progress` two-phase check-in**
(ADR-033 I8 rejected; learning `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`).

## Phase 0 — Evidence-gather & discriminate (NO code)
- [x] 0.1 Query (DONE — routine_runs via Doppler pooler: ZERO terminal rows 06-16→06-21 = SIGKILL signature; 06-22+ ~300ms fast-fail) `routine_runs` for `cron-community-monitor` 2026-06-13→06-21 (read-only SQL /
  Supabase MCP): per-day AND per-attempt `start_lag`, `duration_ms`, `status`, null-`ended_at`
  (SIGKILL signature), `error_summary`, `trigger_source`, `run_id`. Join dual-issue days on Inngest
  run-group/attempt index (retry-after-kill vs. manual).
- [x] 0.2 Pull Better (DONE — retention-blocked: ~1h hot window; incident window aged out) Stack stdout tail (`scripts/betterstack-query.sh` under `doppler run -p soleur
  -c prd_terraform`; query creds in `prd_terraform`, see `runbooks/betterstack-log-query.md`) for
  `fn: 'cron-community-monitor'` — SIGKILL/container-swap markers, `cron-sentry-heartbeat/fetch`
  swallowed-POST warning, last `sentry-heartbeat` log line per run.
- [x] 0.3 Pull Sentry (DONE — checkins confirm last-ok 06-12, missed 06-13→06-21, error 06-22+; issues endpoint 403 no event:read but routine_runs refutes H3) checkins timeline (`GET …/monitors/scheduled-community-monitor/checkins/`) +
  `feature:cron-sentry-heartbeat op:fetch` events (H3 signal).
- [x] 0.4 WebFetch the Sentry Crons HTTP check-in ingest docs; confirm `?status=` shape/enum, the
  missed/timed-out state machine, repeated-POST idempotency. Pin `<!-- verified: 2026-06-29 source: … -->`.
  VERIFIED: URL `/api/<project>/cron/<slug>/<key>/?status=<ok|error|in_progress>`; missed/timeout are
  Sentry-server-generated (not client-reported) ⇒ `missed` proves no POST arrived. `<!-- verified: 2026-06-29 source: https://docs.sentry.io/product/crons/getting-started/http/ -->`
- [x] 0.5 Write the per-day H1/H2/H3/H4 verdict to the PR body + a learning; set which later phase
  is load-bearing.

## Phase 1 — Heartbeat POST robustness (`_cron-shared.ts`)
- [x] 1.1 (RED) cron-shared.test.ts: stubbed 5xx → `reportSilentFallback` fires (today swallowed);
  5xx-then-200 → one effective check-in; all-5xx → one fallback within the wall-clock cap; 4xx → no
  retry.
- [x] 1.2 Add `resp.ok` inspection to `postSentryHeartbeat`; bounded retry on 5xx/network/timeout
  only (NEVER 4xx), total ≤ ~25s; keep `reportSilentFallback` as terminal fallback.
- [x] 1.3 (GREEN) tests pass.

## Phase 2 — Guaranteed terminal heartbeat on the THROW path (flag pattern)
- [x] 2.1 (RED) cron-community-monitor.test.ts: final-attempt no-output throw → one `?status=error`;
  non-final throw → no heartbeat step + rethrow; happy path → one `ok`; no double-signal under
  replay; trailing `safe-commit-pr` throw on output-present run stays GREEN;
  `DeployInProgressError` → no heartbeat + rethrow (both catches).
- [x] 2.2 Extract a shared flag/skip-on-non-final heartbeat wrapper in `_cron-shared.ts` (mirror
  `cron-stale-deferred-scope-outs.ts:358,397-433`). Thread `attempt`/`maxAttempts`.
- [x] 2.3 Adopt in `cron-community-monitor.ts`: catch→`heartbeatOk=false` flag, one last heartbeat
  step; carry computed `heartbeatOk` so a trailing persistence throw on an output-present run stays
  green; exclude `DeployInProgressError`; **fix the existing first catch (`:332-347`)** to rethrow
  `DeployInProgressError` with no heartbeat.
- [x] 2.4 (GREEN) tests pass.
- [x] 2.5 Cohort rollout — grep each output-aware producer's step order; adopt the shared wrapper
  only where the single-last-heartbeat invariant holds; preserve `resolveBestEffortEvalOk` carve-out.

## Phase 3 — IaC + runbook
- [x] 3.1 NO margin change — Phase 0 verdict H2(SIGKILL)-dominant; H1/H4 only plausible on
  routine_runs-blind days. Per plan "H2/H3 only → leave margin at 60, no TF diff."
  `cron-monitors.tf` untouched.
- [x] 3.2 Add runbook H11 (missed-vs-error on a digest-producing claude-eval cron; Phase-0 recipe;
  cross-link H10).

## Phase 4 — ADR
- [x] 4.1 Amend ADR-033 I8 (`/soleur:architecture`): gap-closure note, reaffirm in_progress
  rejection, record the rejection-cost (late/retry finish cannot reconcile → margin is the only lever).

## Verify
- [ ] `tsc --noEmit` clean (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`); full suite
  green incl. `sentry-monitor-iac-parity.test.ts`; `grep in_progress apps/web-platform/server/inngest/`
  shows no POST.
- [ ] Create `scripts/followthroughs/community-monitor-checkin-soak-5728.sh`; enroll the 7-day soak
  (tracker directive + `follow-through` label + sweeper `SENTRY_AUTH_TOKEN`).
- [ ] Post-merge: confirm next fire posts `ok` within margin via the Sentry checkins API (no SSH).
