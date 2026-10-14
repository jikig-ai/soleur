---
lane: cross-domain
brand_survival_threshold: single-user incident
plan: "knowledge-base/project/plans/2026-05-30-feat-inngest-oneshot-4650-monitor-close-plan.md"
issue: "#4654"
---

# Tasks: Inngest oneshot #4650 monitor-close + self-arm + ADR-046

## Phase 0 — Preconditions
- [ ] 0.1 `gh issue view 4650 --json state` — confirm OPEN (else: documented-example only, still ship pattern+ADR)
- [ ] 0.2 Confirm `server/index.ts` `.catch()` boot-side-effect precedent (~:98) + `sendInngestWithRetry` re-throws after retry exhaustion
- [ ] 0.3 **HARD GATE:** verify past-`ts` `inngest.send` delivers on next tick against the RUNNING self-hosted Inngest (ADR-030), not just SDK docs. Unverified → fallback: drop `ts`, send immediate, gate on date guard only
- [ ] 0.4 Confirm `reportSilentFallback` + warn-level variant in `server/observability.ts`

## Phase 1 — Export registry-read primitive
- [ ] 1.1 Add `export` to `fetchRegistry` ONLY in `cron-inngest-cron-watchdog.ts` (NOT `INNGEST_HOST_FALLBACK`)
- [ ] 1.2 Bump `function-registry-count.test.ts` count assertion 41→42 (line ~94)
- [ ] 1.3 Run `test-all.sh` — watchdog suites incl. orphan/scope guards stay green

## Phase 2 — oneshot-4650-monitor-close.ts (TDD)
- [ ] 2.1 RED: write `test/server/inngest/oneshot-4650-monitor-close.test.ts` (path matches vitest `test/**/*.test.ts`): date-guard before/on/after + invalid-calendar-date; already-closed-but-unhealthy alerts; all-3-OK closes; partial/empty registry → leave open, no comment; fetch-throw → fail-safe no close
- [ ] 2.2 GREEN: implement handler (template: `oneshot-recheck-4217-calibration.ts` for `mintInstallationToken`+close). Steps: D3 on-or-after guard (shape+validity, warn-level reject) → check-issue-state (load-bearing idempotency; if closed-but-unhealthy → `reportSilentFallback` op=already-closed-unhealthy) → classify-registry (`resolveInngestHost(process.env.INNGEST_BASE_URL)`, 3 fnIds) → decide (all-OK closes w/ "cron triggers re-planned" wording; else `reportSilentFallback`, no comment)
- [ ] 2.3 `cron-platform` concurrency, `retries:1`, event-only trigger, NO Sentry monitor, `actor:"platform"`, no `runWithByokLease`

## Phase 3 — Self-arm
- [ ] 3.1 In `server/index.ts` `app.prepare().then()`: guarded `void (async()=>{ try { await sendInngestWithRetry(() => inngest.send({id:"oneshot-4650-close-2026-05-31-v1", ts:2026-05-31T09:00Z, data:{issue:4650, expected_date:"2026-05-31", actor:"platform"}}), {feature:"oneshot-4650-arm"}) } catch(err) { reportSilentFallback(err, {feature:"oneshot-4650-arm", op:"self-arm-send"}) } })()` — NOT a bare `.catch()`; must not block `server.listen`

## Phase 4 — Register + ADR
- [ ] 4.1 `app/api/inngest/route.ts`: import + functions-array entry (manual, RV6)
- [ ] 4.2 ADR-046 (scoped to registered-only K3/K21 + self-arm-in-code; cross-link GHA boundary)
- [ ] 4.3 `tsc --noEmit` clean; `grep -r SENTRY_API_TOKEN` empty in diff

## Phase 5 — Ship
- [ ] 5.1 PR body uses `Ref #4650` (NOT `Closes` — close happens at fire time); `Closes #4654`
- [ ] 5.2 user-impact-reviewer at review time (single-user threshold)
