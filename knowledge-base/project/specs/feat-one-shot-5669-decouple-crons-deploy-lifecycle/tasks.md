---
feature: decouple heavy Claude-eval crons from the app deploy lifecycle (graceful drain — Option 1)
issue: 5669
branch: feat-one-shot-5669-decouple-crons-deploy-lifecycle
plan: knowledge-base/project/plans/2026-06-29-fix-infra-decouple-crons-deploy-graceful-drain-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — graceful cron drain before container swap (#5669)

Derived from the plan. Resolve the Domain-Review carried gap checklist (G1–G19) as you go — each task cites the gaps it closes. CPO sign-off required before /work begins (single-user-incident threshold).

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Read the `ci-deploy.sh` stop sequence + locate the canary teardown point in the `:744–763` swap (drain must sit AFTER teardown).
- [ ] 0.2 Read the existing trap topology (EXIT `:137`, TERM INT `:171`, ERR `:176`) + `set -euo pipefail` `:2` — resume must compose, not clobber (G2).
- [ ] 0.3 Run `inngest pause` against a LIVE in-flight cron; confirm (a) stops new dispatch, (b) does NOT abort the running child, (c) gates event-driven invokes (manual trigger, agent-runtime) too (G1/G7). Decides pause/resume vs lease fallback.
- [ ] 0.4 Pin the detection signal by RUNNING it against a live cron; must be pool-agnostic (cron-platform limit:1 + agent-runtime limit:50 + cc-go); add probe timeout (G5/G8/G16).
- [ ] 0.5 Confirm `CRON_WORKSPACE_ROOT` prod value (lease-fallback path).
- [ ] 0.6 Enumerate all per-function `MAX_TURN_DURATION_MS`; compute MAX (4200s, growth-audit).

## Phase 1 — Constants + detection helper (RED→GREEN, ci-deploy.test.sh)

- [ ] 1.1 Define `CRON_DRAIN_TIMEOUT` (default MAX = 4200s), `CRON_DRAIN_POLL` (10s), `DEPLOY_WALL_CLOCK` (4800s) in a SHARED sourced file readable by ci-deploy.sh AND ci-deploy-wrapper.sh (exec boundary — P1-wrapper).
- [ ] 1.2 Test asserts `CRON_DRAIN_TIMEOUT ≥ max per-function ceiling` (T9).
- [ ] 1.3 `cron_in_flight()` wrapping the Phase-0 signal with its own timeout; side-effect-free + mockable.

## Phase 2 — Start-race close via native inngest pause/resume (RED→GREEN)

- [ ] 2.1 `inngest_pause` (|| true under set -e, G6) + composed-EXIT/TERM-INT `inngest_resume` (G2); resume = exit-code check + bounded --max-time retry + loud alert, not `|| true` (G4).
- [ ] 2.2 Resume sequenced AFTER new-container Inngest function-sync (G11), only on swap success (G14).
- [ ] 2.3 Resume-if-paused-at-entry idempotent reconcile (un-wedge after untrappable SIGKILL, G3).
- [ ] 2.4 Lease fallback (only if Phase-0 G1 rules pause out): substrate step-entry check + LEASE_MAX_AGE TTL + pino log.

## Phase 3 — Wall-clock four-constant lockstep + drain gate (RED→GREEN)

- [ ] 3.1 Raise wrapper literal + 3 release-workflow window constants (STATUS/HEALTH/IN_FLIGHT_CEILING_S) in lockstep to 4800 (four-way equality assertion blocks deploy otherwise).
- [ ] 3.2 Drain gate AFTER canary teardown, BEFORE old-prod stop (memory-dwell fix); prod-swap branch only, after CANARY_HEALTHY==true (G10).
- [ ] 3.3 `report_cron_drain_timeout` (|| true) — loud Sentry + deploy-state field on the only cron-killing path.

## Phase 4 — Observability (no-SSH)

- [ ] 4.1 `cat-deploy-state.sh`: `cron_drain_wait_secs` (int), `cron_drain_timed_out` (bool), `inngest_paused` (bool, QUERIED from Inngest not self-reported — G17), safe sentinels.
- [ ] 4.2 `report_cron_drain_timeout` Sentry emit (event_type=cron-drain-timeout, feature=ci-deploy) mirroring container-restart-monitor.sh.

## Phase 5 — Tests

- [ ] 5.1 ci-deploy.test.sh T1–T9 (drain survival/max-ceiling, bounded+set-e, no-cron fast path, pause/resume-no-clobber, resume-if-paused reconcile, canary-torn-down-before-drain, hung-probe-timeout, set-e-no-abort, ceiling assertion).
- [ ] 5.2 cat-deploy-state.test.sh: three new fields + types; inngest_paused queried.
- [ ] 5.3 (lease fallback only) vitest substrate early-return test under test/server/.
- [ ] 5.4 Green: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run <test>`; `bash apps/web-platform/infra/ci-deploy.test.sh` + `cat-deploy-state.test.sh`.

## Phase 6 — ADR + tracking issue

- [ ] 6.1 Create ADR-078 via /soleur:architecture (Decision, Alternatives w/ Option-2 deferred + re-eval (a)-(e), named loosening trade-offs, C4 no-impact enumeration).
- [ ] 6.2 File Option-2 (isolated cron-worker) tracking issue with ADR-078 re-eval criteria; verified-existing label.

## Post-merge (automated, no-SSH)

- [ ] P.1 AC10: first deploy landing mid-cron shows `cron_drain_wait_secs > 0` + `cron_drain_timed_out=false`; `:706` symptom absent (webhook read).
- [ ] P.2 AC11: 72h no spurious `cron_drain_timed_out` on no-cron deploys (Sentry frequency 0).
