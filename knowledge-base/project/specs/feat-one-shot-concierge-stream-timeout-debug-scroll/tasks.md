---
title: "Tasks — Concierge stream timeout + Debug stream autoscroll"
branch: feat-one-shot-concierge-stream-timeout-debug-scroll
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md
---

# Tasks

Derived from `2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md` (post-deepen). Single path: re-arm the server idle watchdog on the SDK `tool_progress` heartbeat. Path B (raise the constant) was deleted at deepen time.

## Phase 0 — Preconditions

- [ ] 0.1 Re-read `agent-runner.ts:1889-1948` (the established server-side `tool_progress` consumer) and confirm cited lines: `SDKToolProgressMessage` at `sdk.d.ts:2504-2513`, `includePartialMessages: true` at `agent-runner-query-options.ts:156`, dropped at `soleur-go-runner.ts:2171`.
- [ ] 0.2 MANDATORY test-enumeration grep: `grep -rn "wallClockTriggerMs\|tool_progress\|runaway\|DEFAULT_WALL_CLOCK_TRIGGER_MS" apps/web-platform/test/` and audit EVERY hit (do not sample). Update any test pinning the old reset semantic.
- [ ] 0.3 Confirm: new component test under `apps/web-platform/test/components/`; typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 0.4 Prepare happy-dom scroll mocks via `Object.defineProperty` (get/set) for `scrollTop`/`scrollHeight`/`clientHeight` on the `<ul>`.

## Phase 1 — Server idle watchdog (TDD)

- [ ] 1.1 RED in `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`: (a) tool_use + N `tool_progress` < 90s apart spanning >90s → no `runner_runaway`; (b) tool_use then SDK silence >90s → STILL fires `runner_runaway` reason=`idle_window` (hung-tool detection preserved).
- [ ] 1.2 GREEN in `soleur-go-runner.ts`: add a `msg.type === "tool_progress"` branch to the dispatch switch (`:2158-2172`) calling `armRunaway(state)` guarded by `!state.closed && !state.awaitingUser`. Touch `state.runaway` ONLY. No field reads (no shape-guard); comment-cite `agent-runner.ts:1901`, `agent-runner-query-options.ts:156` (precondition), and the plan.
- [ ] 1.3 Server-internal only — NO new WS message type, NO client forward (cc-dispatcher does not forward `tool_progress` today; chip-regression guard moot). Client 45s residual → Follow-ups.
- [ ] 1.4 REFACTOR + run the watchdog test file (and anything surfaced by 0.2).

## Phase 2 — Debug stream sticky autoscroll (TDD)

- [ ] 2.1 RED: `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` — (a) pin at bottom sets `scrollTop=scrollHeight`, (b) no yank when scrolled up, (c) resume on scroll-back.
- [ ] 2.2 GREEN in `debug-stream-panel.tsx`: `useRef` on the `<ul>` (no sentinel `<li>`); `stickToBottom = useRef(true)` (NOT state); `const STICK_TO_BOTTOM_THRESHOLD_PX = 32`; `onScroll` sets `stickToBottom.current = (scrollHeight - scrollTop - clientHeight) < THRESHOLD`; `useEffect([events.length])` does `ul.scrollTop = ul.scrollHeight` only when `stickToBottom.current`. Keep oldest-at-top order.
- [ ] 2.3 REFACTOR + run the two debug-panel test files.

## Phase 3 — Typecheck + suite + ADR

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 3.2 `vitest run` the watchdog + two debug-panel test files (+ anything from 0.2).
- [ ] 3.3 Append ADR-022 one-line amendment: three `state.runaway` reset triggers (block / `tool_use_result` / `tool_progress`), `turnHardCap` fed by none. Closes #3225 follow-up debt.
- [ ] 3.4 QA: no spurious "Agent stopped responding" on a long single-tool turn; debug panel stays pinned to newest unless scrolled up.
