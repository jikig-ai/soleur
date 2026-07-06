---
title: "Tasks — Concierge duplicate question box + Still-working fix"
branch: feat-one-shot-concierge-web-duplicate-question-box
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-06-fix-concierge-duplicate-question-and-still-working-plan.md
date: 2026-07-06
---

# Tasks

Derived from `2026-07-06-fix-concierge-duplicate-question-and-still-working-plan.md`.

## Phase 1 — De-duplicate (server emit)

- [ ] 1.1 In `apps/web-platform/server/soleur-go-runner.ts`, change the `case "AskUserQuestion":`
      arm of `classifyInteractiveTool` (currently ~661-687) to `return null`, with a comment
      mirroring the `Bash` precedent (~646-660): the amber `review_gate` (permission-callback.ts) is
      the single authoritative surface; the `ask_user` card is redundant. Keep `ask_user` in the
      `InteractivePromptPayload` union + `InteractivePromptCard` for replay back-compat.
- [ ] 1.2 Add the P2b co-installation note in the same comment: the `AskUserQuestion` review_gate
      (`permission-callback.ts:268`, unconditional `canUseTool` interception) is the co-installed
      replacement surface; guards a future wiring split from reintroducing a no-surface state.
- [ ] 1.3 Confirm `permission-callback.ts` (AskUserQuestion → review_gate) is untouched and still the
      surviving surface; `bridgeInteractivePromptIfApplicable` returns before `pendingPrompts.register`
      on `null`, so no dangling registry entry.

## Phase 2 — Suppress "Still working…" while awaiting input (client render)

- [ ] 2.1 In `apps/web-platform/components/chat/chat-surface.tsx`, derive (near the narration slot
      ~982, where `messages` + `streamState` are in scope):
      `const lastUserIdx = messages.map(m => m.role).lastIndexOf("user");`
      `const awaitingUserInput = messages.some((m, i) => i > lastUserIdx && (m.type === "review_gate" || m.type === "autonomous_disclosure") && !m.resolved);`
      — NOT `interactive_prompt` (informational kinds stream while working; plan-review P1); turn-scoped
      via `i > lastUserIdx` (stale gates must not dark later turns; plan-review P2a).
- [ ] 2.2 Change the live-narration slot guard from `streamState === "streaming"` to
      `streamState === "streaming" && !awaitingUserInput`; update the block comment to note the
      awaiting-input suppression (keep the reconnect-null rationale).

## Phase 3 — Tests

- [ ] 3.1 `apps/web-platform/test/soleur-go-runner-interactive-prompt.test.ts` — replace the
      AskUserQuestion→ask_user emission case (~231) with a suppression assertion (no
      `interactive_prompt` / no pending prompt). Mirror the Bash-suppression assertion.
- [ ] 3.2 `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` — assert the amber
      `review_gate` card is the sole question surface; no `data-prompt-kind="ask_user"`.
- [ ] 3.3 Create `apps/web-platform/test/chat-surface-awaiting-input.test.tsx` (jsdom) — with the
      `test/mocks/use-websocket.ts` mock, five cases: (AC3) streaming + unresolved current-turn
      review_gate → `live-narration` absent; (AC4) streaming + no gate → present; (AC5) streaming +
      resolved gate → present; (AC5b) streaming + unresolved informational `interactive_prompt`
      (diff/todo_write), no gate → present; (AC5c) streaming + unresolved review_gate BEFORE the last
      `user` message (stale) → present. Path under `test/` to match the vitest `.test.tsx` glob.

## Phase 4 — Verify

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC6).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-interactive-prompt.test.ts test/cc-soleur-go-end-to-end-render.test.tsx test/reasoning-narration-frame.test.ts test/chat-surface-awaiting-input.test.tsx` (AC1-5, AC7).
