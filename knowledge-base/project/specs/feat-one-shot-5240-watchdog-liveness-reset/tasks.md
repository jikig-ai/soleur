---
title: "Tasks — fix watchdog false-positive (leader-liveness bounded reset)"
plan: knowledge-base/project/plans/2026-06-15-fix-watchdog-false-positive-leader-liveness-reset-plan.md
branch: feat-one-shot-5240-watchdog-liveness-reset
parent_epic: 5240
lane: single-domain
brand_survival_threshold: single-user incident
---

# Tasks — watchdog leader-liveness bounded reset

Derived from the deepened plan. TDD mandate (`cq-write-failing-tests-before`): author the RED tests in
Phase 2 BEFORE the implementation in Phase 3. Runner is **vitest**, not bun:
`cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Typecheck:
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`).

## Phase 1 — Preconditions (re-verify before coding)

- [ ] 1.1 Re-grep the reducer arms that emit `timerAction`:
      `grep -n "case \|timerAction" apps/web-platform/lib/chat-state-machine.ts` — confirm `debug_event`
      (`~:1032`) still emits NONE and `applyTimeout` Stage-2 (`~:1104-1116`) still escalates unconditionally.
- [ ] 1.2 Confirm `debug_event` carries no `leaderId` (`apps/web-platform/lib/types.ts:341-346`) and the
      `clear_all` precedent shape in `ws-client.ts:617` + `clearAllTimeouts` (`:576-581`).
- [ ] 1.3 Confirm vitest include globs (`apps/web-platform/vitest.config.ts:44,60`) and that the harness in
      `test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` is the pattern to mirror.

## Phase 2 — RED tests first (must FAIL on base @ e62b19bda)

- [ ] 2.1 `test/chat-state-machine.test.ts` — **AC1** single-leader debug-liveness: `debug_event{kind:"tool_use"}`
      with `activeStreams.size === 1` → `timerAction === {type:"reset_all"}`, bubble `retrying` cleared,
      `livenessRearms === 0`. (FAILS today — debug emits no timerAction.)
- [ ] 2.2 **AC2** multi-bubble cross-leader (pinned): A `retrying` + B active → `applyTimeout(…, "A")` keeps
      A `tool_use`, `retrying:true`, `livenessRearms === 1`, `timerAction === {type:"reset", leaderId:"A"}`,
      `activeStreams.has("A")`. (FAILS today — A escalates regardless of B.)
- [ ] 2.3 **AC3** genuine-hang single leader (standalone, bracketed with the AC2 two-leader seed): only A
      active, `retrying` → escalates to `error` + removed from `activeStreams`.
- [ ] 2.4 **AC3b** bounded re-arm un-masks: A `retrying` + B always active; loop `applyTimeout(…, "A")`
      `MAX_LIVENESS_REARMS + 1` times → re-arms 1..MAX (`livenessRearms` increments), escalates on MAX+1
      despite B active.
- [ ] 2.5 **AC3c** re-arm then all-silent: A re-armed (B active) → remove B → `applyTimeout(…, "A")` escalates A.
- [ ] 2.6 **AC7** ceiling negatives: (a) `size===0` debug → no timerAction; (b) `size>1` debug `tool_use` →
      no `reset_all`; (c) `kind:"reasoning"` and `kind:"result"` → no `reset_all`.
- [ ] 2.7 **AC8b** no resurrection: sole active bubble is `error`/`done` but in `activeStreams`; debug
      `reset_all` re-arms timer but follow-up `applyTimeout` no-ops (`:1099` guard) → no state change.
- [ ] 2.8 `test/message-bubble-retry.test.tsx` — **AC4** Stage-1 `retrying` bubble renders honest "No
      response yet" chip, NEVER "Agent stopped responding". Existing `:59`/`:80` error-render tests stay.
- [ ] 2.9 Run the suite, confirm 2.1/2.2/2.4/2.5/2.6/2.7 FAIL (RED) and 2.3/2.8 reflect preserved behavior.

## Phase 3 — Implementation (make GREEN)

- [ ] 3.1 `chat-state-machine.ts`: add `livenessRearms?: number` to `ChatMessageBase` (`:31-54`); add
      `export const MAX_LIVENESS_REARMS = 3;` (here or `ws-constants.ts`).
- [ ] 3.2 Extend `applyStreamEvent` `timerAction` return union (`:302-305`) with `| { type: "reset_all" }`.
      Do NOT widen `applyTimeout`'s union.
- [ ] 3.3 `debug_event` case (`:1032-1055`): emit `{type:"reset_all"}` only when `kind==="tool_use"` AND
      `activeStreams.size === 1`; in that arm clear `retrying` + reset `livenessRearms` on the sole bubble.
      Rewrite the orthogonal-panel comment (`:1036-1039`) to record the new heartbeat + the `size===1` /
      `:1099`-guard safety rationale (and the debug-is-live-only invariant re #5290).
- [ ] 3.4 `applyTimeout` Stage-2 arm (`:1104-1116`): if any OTHER leader (`!== leaderId`) is active in
      `activeStreams` with a transitional/streaming bubble AND `livenessRearms < MAX_LIVENESS_REARMS` →
      increment `livenessRearms`, keep `retrying:true`, return `{type:"reset", leaderId}`. Else escalate to
      `error` + delete from `activeStreams`.
- [ ] 3.5 `ws-client.ts`: add `resetAllTimeouts` mirroring `clearAllTimeouts` (`:576-581`) iterating
      `timeoutTimersRef.current.keys()`; wire `ta.type === "reset_all"` in the `useEffect` if-ladder (`:612-619`).
- [ ] 3.6 Run the Phase-2 suite → all GREEN.

## Phase 4 — Verify + sweep

- [ ] 4.1 **AC6** type-widening: `git grep -n "pendingTimerAction\|timerAction" apps/web-platform/` — confirm
      the if-ladder handles `reset_all`; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 4.2 **AC5** `git grep -n "reset_all\|resetAllTimeouts" apps/web-platform/lib/ws-client.ts` returns the
      branch + helper beside `clearAllTimeouts` (`:617`).
- [ ] 4.3 **AC8** full suite green: `cd apps/web-platform && ./node_modules/.bin/vitest run
      test/chat-state-machine.test.ts test/message-bubble-retry.test.tsx
      test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` (the cc-soleur-go regression stays green).
- [ ] 4.4 Confirm debug-event persistence CI grep gate unaffected
      (`git grep -n "debug_event" apps/web-platform/lib/ws-handler.ts`).

## Phase 5 — Ship

- [ ] 5.1 File the focused sub-issue under #5240 (labels: `type/bug`, `app:web-platform`,
      `domain/engineering`, `priority/p2-medium`).
- [ ] 5.2 PR body: `Ref #5240` (keep parent open) + `Closes #<sub-issue>`. Pre-merge ACs in `### Pre-merge`,
      post-merge None.
- [ ] 5.3 Standard `/soleur:ship` → `/soleur:qa` → merge. Merge IS the deploy (`web-platform-release.yml`
      path-filtered on `apps/web-platform/**`).
