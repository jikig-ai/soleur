---
title: "Tasks — V2 CC hardening (#3040)"
plan: knowledge-base/project/plans/2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md
issue: 3040
related_closes: [3369]
---

# Tasks — V2 CC hardening

Derived from `knowledge-base/project/plans/2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md`.

## Phase 1 — Extract `safe-bash.ts` (Finding 1)

- [ ] 1.1 Create `apps/web-platform/server/safe-bash.ts` with regex constants + `isBashCommandSafe`.
- [ ] 1.2 Keep `NEAR_MISS_STATE: WeakMap<CanUseToolContext, ...>` in `permission-callback.ts` (cyclic-import avoidance).
- [ ] 1.3 Update `permission-callback.ts` to import + re-export the symbols.
- [ ] 1.4 Move `permission-callback-safe-bash.test.ts` import path to `@/server/safe-bash`.
- [ ] 1.5 Run `bun test apps/web-platform/test/permission-callback-safe-bash.test.ts apps/web-platform/test/permission-callback-bash-batch.test.ts` — 0 regressions.
- [ ] 1.6 Commit `refactor(safe-bash): extract regex allowlist module from permission-callback`.

## Phase 2 — `mirrorWithDebounce` extraction (Findings 2 + #3369)

- [ ] 2.1 Add `mirrorWithDebounce`, `MIRROR_DEBOUNCE_MS`, `_mirrorLastReportedAt` to `observability.ts`.
- [ ] 2.2 Delete local copy from `cc-dispatcher.ts`; replace with import.
- [ ] 2.3 Migrate `kb-document-resolver.ts` to use `mirrorWithDebounce` with errorClass derived from `extractPdfText` failure class.
- [ ] 2.4 Create `apps/web-platform/test/observability-mirror-debounce.test.ts` (5 cases).
- [ ] 2.5 Run `bun test apps/web-platform/test/cc-dispatcher.test.ts apps/web-platform/test/observability-mirror-debounce.test.ts`.
- [ ] 2.6 Commit `refactor(observability): extract mirrorWithDebounce (Closes #3369)`.

## Phase 3 — `reapIdle` consults `awaitingUser` (Finding 3)

- [ ] 3.1 Add `&& !state.awaitingUser` predicate in `reapIdle`.
- [ ] 3.2 Add `log.debug` for paused-skip case.
- [ ] 3.3 Route `notifyAwaitingUser` no-active-query branch through `mirrorWithDebounce`.
- [ ] 3.4 Export `NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS` const.
- [ ] 3.5 Add AC9 (reaper skip) + AC12 (mirror debounce) tests.
- [ ] 3.6 Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`.
- [ ] 3.7 Commit `fix(cc): idle-reaper skips paused conversations + notify-awaiting silent fallback debounced (#3040)`.

## Phase 4 — Paused-interval subtraction (Finding 4)

- [ ] 4.1 Add `pausedAt: number | null` and `totalPausedMs: number` to `ActiveQuery` interface.
- [ ] 4.2 Update `notifyAwaitingUser`: stamp `pausedAt` on true / accumulate `totalPausedMs` on false. Remove `firstToolUseAt = now()` re-stamp.
- [ ] 4.3 Update `armRunaway` and `armTurnHardCap` fire-time: re-arm if `elapsedMs < threshold` after subtracting paused intervals.
- [ ] 4.4 Update `recordAssistantBlock` (first-block-of-turn): reset `totalPausedMs = 0; pausedAt = null`.
- [ ] 4.5 Update `closeQuery` + `dispatch()` initializer for the new fields.
- [ ] 4.6 Add AC10 (90s window cumulative across flap) + AC11 (10-min ceiling cumulative across pause) tests.
- [ ] 4.7 Add multi-turn test (paused state reset on new turn).
- [ ] 4.8 Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts apps/web-platform/test/soleur-go-runner-lifecycle.test.ts apps/web-platform/test/soleur-go-runner-tool-result-idle-reset.test.ts`.
- [ ] 4.9 Commit `fix(cc): wall-clock subtracts paused intervals across rapid status flap (#3040)`.

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
