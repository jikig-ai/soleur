---
title: "Tasks — Concierge stream timeout + Debug stream autoscroll"
branch: feat-one-shot-concierge-stream-timeout-debug-scroll
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md
---

# Tasks

Derived from `2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md`.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm the SDK's mid-tool forward-progress message discriminator by reading the installed `@anthropic-ai/claude-agent-sdk` `.d.ts` (the message that fires DURING a single long tool execution, not only at tool boundaries). Determine Path A (heartbeat reset) vs Path B (bounded raise).
- [ ] 0.2 If no mid-tool SDK signal exists, take Path B and pre-write the `turnHardCap`-as-ceiling justification per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`.
- [ ] 0.3 Confirm vitest globs: new component test under `apps/web-platform/test/components/`; typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 0.4 Prepare happy-dom scroll mocks (`scrollIntoView`, `scrollTop`/`scrollHeight`/`clientHeight`).

## Phase 1 — Server idle watchdog (TDD)

- [ ] 1.1 RED: add failing test in `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` — single tool + mid-tool forward-progress signals spanning >90s must NOT fire `runner_runaway` (Path A) / assert raised window (Path B).
- [ ] 1.2 GREEN: re-arm `state.runaway` on the SDK mid-tool signal in `soleur-go-runner.ts` (guarded by `!closed && !awaitingUser`, mirroring `handleUserMessage`), touching `state.runaway` ONLY — never `state.turnHardCap`. (Path B: raise `DEFAULT_WALL_CLOCK_TRIGGER_MS` + document ceiling.)
- [ ] 1.3 Confirm no double-emit / no new WS chip if the signal is also forwarded to client (`tool_progress` chip-regression guard at `chat-state-machine.ts:498-500`). Default: server-internal reset only, no new WS message type.
- [ ] 1.4 REFACTOR + run `vitest run test/soleur-go-runner-awaiting-user.test.ts`.

## Phase 2 — Debug stream sticky autoscroll (TDD)

- [ ] 2.1 RED: `apps/web-platform/test/components/debug-stream-panel-autoscroll.test.tsx` — cases (a) pin at bottom, (b) no yank when scrolled up, (c) resume on scroll-back. Mock scroll APIs.
- [ ] 2.2 GREEN: in `debug-stream-panel.tsx` add `useRef` on the `<ul>` (or bottom sentinel `<li>`), `stickToBottom` flag, `onScroll` handler, and a `useEffect` keyed on `events` that scrolls to bottom only when `stickToBottom`. Keep oldest-at-top order.
- [ ] 2.3 REFACTOR + run the two debug-panel test files.

## Phase 3 — Typecheck + suite

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 3.2 `vitest run` the watchdog + debug-panel + state-machine + error-bubble test files.
- [ ] 3.3 QA: no spurious "Agent stopped responding" on a long single-tool turn; debug panel stays pinned to newest unless scrolled up.
