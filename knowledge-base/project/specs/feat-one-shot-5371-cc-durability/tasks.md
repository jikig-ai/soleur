---
title: "Tasks — cc-soleur-go durability follow-ups"
issue: 5371
branch: feat-one-shot-5371-cc-durability
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-15-chore-cc-soleur-go-durability-followups-plan.md
---

# Tasks — cc-soleur-go durability follow-ups (#5371)

Derived from the finalized (post-review) plan. Two backend wiring gaps:
idle-reaper scheduling + SIGTERM cc-drain. Both match existing precedents.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Confirm `reapIdle()` still unscheduled: `git grep -nE 'setInterval.*reapIdle|reapIdle\(\)' apps/web-platform/server/`.
- [ ] 0.2 Read `startStuckActiveReaper` (`agent-runner.ts:773-849`) — note `timer.unref()` at :848 (the cc reaper must match).
- [ ] 0.3 Read `index.ts` SIGTERM handler region — anchor edits to symbols (`clearInterval(stuckActiveReaperTimer)`, `abortAllSessions()`, `streamReplayBuffer.clearAll()`), NOT line numbers.
- [ ] 0.4 Read `soleur-go-runner.ts` interface (`:1125-1170`), return object (`:3236-3244`), and `closeQuery` body (`:1949-1995`) — confirm no `state.closed` early-return in the body (caller-side guard only).

## Phase 1 — Gap 1: schedule the cc idle reaper

- [ ] 1.1 In `cc-dispatcher.ts`: add local `const CC_IDLE_REAPER_INTERVAL_MS = 300_000` (commented re ≤ `DEFAULT_IDLE_REAP_MS`, not exported).
- [ ] 1.2 In `cc-dispatcher.ts`: add exported `reapIdleCcQueries(): number` with `if (!_runner) return 0;` guard → `_runner.reapIdle()`.
- [ ] 1.3 In `cc-dispatcher.ts`: add exported `startCcIdleReaper(): NodeJS.Timeout` — `setInterval` calling `reapIdleCcQueries()` in `try/catch → reportSilentFallback({feature:"cc-idle-reaper", op:"reap"})`; call `timer.unref()` before return.
- [ ] 1.4 In `index.ts`: `const ccIdleReaperTimer = startCcIdleReaper()` right after `startStuckActiveReaper()` call.
- [ ] 1.5 In `index.ts` SIGTERM handler: `clearInterval(ccIdleReaperTimer)` right after `clearInterval(stuckActiveReaperTimer)`.

## Phase 2 — Gap 2: drain cc queries on SIGTERM (no checkpoint) — contract-first order

- [ ] 2.1 In `soleur-go-runner.ts`: add `closeAllForShutdown(): number` to interface (`:1125`) + return object (`:3240`) + impl (near `:3126`). Iterate `activeQueries`; for each `state.closed !== true`, set `state.closed = true` and `closeQuery(state)` (NO reason). Do NOT skip `awaitingUser`. Return count.
- [ ] 2.2 In `cc-dispatcher.ts`: add exported `drainCcQueriesForShutdown(): number` with `if (!_runner) return 0;` → `_runner.closeAllForShutdown()`.
- [ ] 2.3 In `index.ts` SIGTERM handler: `const drained = drainCcQueriesForShutdown()` right after `abortAllSessions()` (before `streamReplayBuffer.clearAll()`); add `log.info({ drained }, "cc drain on shutdown")`.

## Phase 3 — Tests (extend existing lifecycle file, RED → GREEN)

Target file: `apps/web-platform/test/soleur-go-runner-lifecycle.test.ts`. `afterEach(() => { vi.useRealTimers(); clearInterval(timer); })`.

- [ ] 3.1 T1 (AC4): drain over active queries with spy `onCloseQuery` → every call `reason === undefined`.
- [ ] 3.2 T2 (AC5): both accessors return 0 / no-op when `_runner` null.
- [ ] 3.3 T3 (AC6): `closeConversation(id,"disconnected")` then drain → `onCloseQuery` fires exactly once for that conversation.
- [ ] 3.4 T4 (AC7): `awaitingUser:true` query skipped by reaper, closed by drain.
- [ ] 3.5 T5 (AC1): fake-timer advance past `CC_IDLE_REAPER_INTERVAL_MS` after `startCcIdleReaper()` → `reapIdle()` ran; timer unref'd.

## Phase 4 — Verify

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-lifecycle.test.ts` passes.
- [ ] 4.3 Re-eval grep satisfied: `git grep -nE 'startCcIdleReaper' apps/web-platform/server/index.ts` ≥1 AND `git grep -n 'drainCcQueriesForShutdown' apps/web-platform/server/index.ts` ≥1.
- [ ] 4.4 Full AC sweep (AC1–AC9 in plan).
