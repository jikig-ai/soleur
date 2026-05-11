---
title: "Tasks — V2 CC hardening (#3040)"
plan: knowledge-base/project/plans/2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md
issue: 3040
related_closes: [3369]
---

# Tasks — V2 CC hardening

Derived from `knowledge-base/project/plans/2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md`.

## Phase 1 — Extract `safe-bash.ts` (Finding 1)

- [x] 1.1 Create `apps/web-platform/server/safe-bash.ts` with regex constants + `isBashCommandSafe`.
- [x] 1.2 Keep `NEAR_MISS_STATE: WeakMap<CanUseToolContext, ...>` in `permission-callback.ts` (cyclic-import avoidance).
- [x] 1.3 Update `permission-callback.ts` to import + re-export the symbols.
- [x] 1.4 Move `permission-callback-safe-bash.test.ts` import path to `@/server/safe-bash`.
- [x] 1.5 Run `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts apps/web-platform/test/permission-callback-bash-batch.test.ts` — 0 regressions.
- [x] 1.6 Commit `refactor(safe-bash): extract regex allowlist module from permission-callback`.

## Phase 2 — `mirrorWithDebounce` extraction (Findings 2 + #3369)

- [x] 2.1 Add `mirrorWithDebounce`, `MIRROR_DEBOUNCE_MS`, `_mirrorLastReportedAt` to `observability.ts`.
- [x] 2.2 Delete local copy from `cc-dispatcher.ts`; replace with import.
- [x] 2.3 Migrate `kb-document-resolver.ts` to use `mirrorWithDebounce` with errorClass derived from `extractPdfText` failure class.
- [x] 2.4 Create `apps/web-platform/test/observability-mirror-debounce.test.ts` (5 cases).
- [x] 2.5 Run `bun test apps/web-platform/test/cc-dispatcher.test.ts apps/web-platform/test/observability-mirror-debounce.test.ts`.
- [x] 2.6 Commit `refactor(observability): extract mirrorWithDebounce (Closes #3369)`.

## Phase 3 — `reapIdle` consults `awaitingUser` + Finding 2 runner integration

- [x] 3.1 Add `&& !state.awaitingUser` predicate in `reapIdle`.
- [x] 3.2 Add `log.debug` for paused-skip case.
- [x] 3.3 Route `notifyAwaitingUser` no-active-query branch through `mirrorWithDebounce` (import from `./observability`; Phase 2 must have landed).
- [x] 3.4 Export `NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS` const at top of `soleur-go-runner.ts`.
- [x] 3.5 **REWRITE** existing test at `soleur-go-runner-awaiting-user.test.ts:407` to mock `mirrorWithDebounce` instead of `reportSilentFallback`.
- [x] 3.6 Add NEW AC11 (reaper-skip-paused) test.
- [x] 3.7 Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts apps/web-platform/test/soleur-go-runner-lifecycle.test.ts`.
- [ ] 3.8 Commit `fix(cc): idle-reaper skips paused conversations + notify-awaiting silent fallback debounced (#3040)`.

## Phase 4 — Paused-interval subtraction + drift sweep (Finding 4)

- [ ] 4.1 Add `pausedAt: number | null` and `totalPausedMs: number` to `ActiveQuery` interface with the JSDoc shown in plan §"Files to Edit".
- [ ] 4.2 Update `notifyAwaitingUser`: stamp `pausedAt` on true / accumulate `totalPausedMs` on false. Remove `firstToolUseAt = now()` re-stamp at line 2518.
- [ ] 4.3 Update `armRunaway` and `armTurnHardCap` fire-time callbacks: compute `elapsedMs = (now() - turnOriginAt) - totalPausedMs - (pausedAt ? now() - pausedAt : 0)`; re-arm via `setTimeout(<callback>, Math.max(1, threshold - elapsedMs))` if too early; log every re-arm at `log.debug`.
- [ ] 4.4 Update `recordAssistantBlock` (inside `if (isFirstBlockOfTurn)`): reset `totalPausedMs = 0; pausedAt = null`.
- [ ] 4.5 Update `closeQuery` (line 1524) + `dispatch()` initializer for the new fields.
- [ ] 4.6 **Drift-sweep** the per-window→cumulative narrative across 6 sites:
  - test docstring `soleur-go-runner-awaiting-user.test.ts:46`
  - REWRITE test at `soleur-go-runner-awaiting-user.test.ts:291` ("AC9: only ACTIVE compute time counts")
  - inline comment `soleur-go-runner-awaiting-user.test.ts:332`
  - runner doc `soleur-go-runner.ts:825-836` (`notifyAwaitingUser` interface JSDoc)
  - runner doc `soleur-go-runner.ts:1229-1236` (`awaitingUser` field)
  - inline comment `soleur-go-runner.ts:2511-2516`
- [ ] 4.7 Verify drift-sweep via `git grep -E "fresh firstToolUseAt|per-active-window|only ACTIVE compute" apps/web-platform/` returns zero hits.
- [ ] 4.8 Add NEW AC12 (10-min absolute ceiling cumulative), NEW AC13 (multi-turn reset), NEW AC14 (mirror debounce 5-min TTL coalescing).
- [ ] 4.9 Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts apps/web-platform/test/soleur-go-runner-lifecycle.test.ts apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts`.
- [ ] 4.10 Commit `fix(cc): wall-clock subtracts paused intervals across rapid status flap + drift sweep per-window→cumulative (#3040)`.

## Phase 5 — Full sweep + review

- [ ] 5.1 `bash scripts/test-all.sh` (parity with #3020 ship gate).
- [ ] 5.2 `bun tsc --noEmit` clean.
- [ ] 5.3 Push branch + open PR with `Closes #3040 #3369` and acknowledgments for #3344 #3343.
- [ ] 5.4 Multi-agent review (architecture-strategist + code-simplicity-reviewer + data-integrity-guardian).
- [ ] 5.5 Address review findings inline.

## Phase 6 — Post-merge dogfood

- [ ] 6.1 Deploy to prd.
- [ ] 6.2 Exercise per AC13 (pwd + >30s read, no runaway, no `notify-awaiting` Sentry).
- [ ] 6.3 24h Sentry event-rate check per AC14.
- [ ] 6.4 Close #3040 and #3369 with verification notes.
