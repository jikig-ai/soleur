# Tasks — fix: make claude-eval cron failures observable (#5674)

Plan: `knowledge-base/project/plans/2026-06-29-fix-claude-eval-cron-failure-observability-plan.md`
Lane: cross-domain · Threshold: single-user incident · requires_cpo_signoff: true

## Phase 0 — Setup & preconditions
- [ ] 0.1 Read the 4 masked cron handlers + `_cron-shared.ts` + `run-log.ts` end-to-end before editing.
- [ ] 0.2 Pull Better Stack history for the 4 masked crons; record healthy-non-zero-exit frequency (R1 decision input).
- [ ] 0.3 Read all three `.c4` model files; determine Anthropic-API / Sentry / routine_runs element coverage.

## Phase 1 — Capture failure reason + unify run-log
- [ ] 1.1 Add `formatTailForSentry()` (multi-secret scrub + slice) to `_cron-shared.ts`.
- [ ] 1.2 Add `resolveBestEffortEvalOk(spawnResult)` to `_cron-shared.ts` (centralizes Phase-2 policy + scrubbed sentryExtra).
- [ ] 1.3 Widen `run-log.ts`: treat `result.data.ok === false` as failed; derive scrubbed `error_summary`; preserve final-attempt gate.
- [ ] 1.4 Unit tests: resolver reason capture, `formatTailForSentry` redaction, run-log failed-on-return + double-write guard.

## Phase 2 — Unify heartbeat policy (4 masked crons)
- [ ] 2.1 `cron-agent-native-audit.ts`: route non-zero through resolver; heartbeat `ok:result.ok`; return errorSummary; update stale comment.
- [ ] 2.2 `cron-legal-audit.ts`: same.
- [ ] 2.3 `cron-ux-audit.ts`: same.
- [ ] 2.4 `cron-bug-fixer.ts`: same (covers the multiple ok:true heartbeats on non-zero/no-PR).
- [ ] 2.5 Per-cron flip-vs-two-phase decision from 0.2; document in PR body.
- [ ] 2.6 Handler tests: non-zero → `postSentryHeartbeat ok:false` + `{ok:false,errorSummary}`.

## Phase 3 — Anthropic credit/usage probe
- [ ] 3.1 Create `cron-anthropic-credit-probe.ts` (hourly; canary via `postAnthropicMessage`; optional admin cost-trend).
- [ ] 3.2 Register in `app/api/inngest/route.ts` functions array.
- [ ] 3.3 Add to `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts`).
- [ ] 3.4 Add `ROUTINE_METADATA` entry (`routine-metadata.ts`).
- [ ] 3.5 Add `scheduled_anthropic_credit_probe` monitor (30-min margin) to `cron-monitors.tf`.
- [ ] 3.6 Bump `function-registry-count.test.ts` (`toBe(56)`→57) + fix slug/tf-monitor assertions; pass parity test.
- [ ] 3.7 Probe tests: credit-exhausted 400 → page; clean → ok; unset admin key → spend branch skipped.
- [ ] 3.8 Confirm no `runWithByokLease` import (ADR-033 I2 sweep test passes).

## Phase 4 — Docs / ADR / C4
- [ ] 4.1 Amend ADR-033 (`## Decision` unified-heartbeat invariant + `## Alternatives Considered` + no-balance-endpoint).
- [ ] 4.2 C4: add missing Anthropic-API / Sentry / routine_runs elements+edges+view-include if absent; run c4 tests. Else cite checked-and-modeled.
- [ ] 4.3 Update `runbooks/cloud-scheduled-tasks.md` with new Sentry ops + triage.

## Phase 5 — Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 5.2 Run inngest + run-log + c4 test suites green.
- [ ] 5.3 Pre-merge AC 1–9 checked; CPO sign-off recorded.

## Post-merge (operator)
- [ ] P.1 After `apply-sentry-infra.yml`, verify `scheduled-anthropic-credit-probe` monitor exists (Sentry API, read-only).
- [ ] P.2 (Deferrable) Provision optional `ANTHROPIC_ADMIN_KEY` + `ANTHROPIC_MONTHLY_BUDGET_USD` in Doppler dev+prd; Playwright-attempt the admin-key mint first (automation-status UNVERIFIED). `Ref #5674`.
