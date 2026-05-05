# Tasks — feat-one-shot-concierge-idle-and-dup-label

Plan: `knowledge-base/project/plans/2026-05-05-fix-concierge-idle-runaway-and-duplicate-label-plan.md`

## Phase 1 — Setup

- 1.1 Verify the worktree branch matches the feat name and the plan file is committed before
  starting the TDD cycle.

## Phase 2 — Bug 1: Runaway timer relaxation (TDD)

- 2.1 (RED) Update `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`. Add a new
  describe block (e.g., `"any-block runaway-reset semantics"`) following the existing
  `notifyAwaitingUser pause/resume` block's pattern (`vi.useFakeTimers`, `flushMicrotasks`,
  `wallClockTriggerMs: 90_000`):
  - 2.1.1 Test: emit one `tool_use`, advance 25s, emit a second `tool_use`, advance another
    70s (95s total elapsed real-time, but only 70s since the second block) — assert
    `runner_runaway` does NOT fire. Then advance another 25s (95s since the second block),
    flush microtasks, assert `runner_runaway` DOES fire.
  - 2.1.2 Test: emit one `tool_use`, advance 25s, emit an assistant `text` block, advance
    another 70s — assert `runner_runaway` does NOT fire. Confirms text resets the window.
  - 2.1.3 Test: emit one `tool_use`, advance 95s with no further blocks, assert
    `runner_runaway` fires with `elapsedMs >= 90_000`.
  - 2.1.4 Test: emit one `tool_use` at t=0, emit another at t=60s, advance to t=160s,
    assert `runner_runaway.elapsedMs >= 150_000` (NOT ~90_000) — pins
    `firstToolUseAt` as turn-origin metadata.
- 2.2 (GREEN) `apps/web-platform/server/soleur-go-runner.ts`:
  - 2.2.1 Change `DEFAULT_WALL_CLOCK_TRIGGER_MS = 30 * 1000` to `90 * 1000` (line 82).
  - 2.2.2 Refactor `handleAssistantMessage` (lines 766-851). For every `text` AND `tool_use`
    block:
    - if `state.firstToolUseAt === null`: set it to `now()` (turn-origin, set ONCE).
    - unconditionally call `clearRunaway(state)` then `armRunaway(state)` IF
      `!state.awaitingUser` and `!state.closed`.
    Move the existing first-tool-use arm-runaway branch out of the `tool_use`-only path so
    the same arm-reset semantic applies to text. Do NOT reset `firstToolUseAt` on
    subsequent blocks (test 2.1.4 enforces this).
  - 2.2.3 Update the comment block (~798-803) describing the wall-clock semantics from
    "FIRST tool_use" to "any assistant block (text or tool_use) resets the timeout window;
    `firstToolUseAt` remains the turn-origin timestamp for `runner_runaway.elapsedMs`".
- 2.3 Run `bun test apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`. Confirm
  all new tests green AND existing AC7-regression / AC8 / AC9 / AC17 / silent-fallback
  tests remain green.

## Phase 3 — Bug 2: Header label deduplication (TDD)

- 3.1 (RED) Create `apps/web-platform/test/message-bubble-header.test.tsx`, modeled on
  `apps/web-platform/test/message-bubble-retry.test.tsx`:
  - 3.1.1 Add the same `vi.mock("@/lib/client-observability")` shim from the retry test.
  - 3.1.2 Test: render `<MessageBubble role="assistant" leaderId="cc_router" showFullTitle
    messageState="done" content="hello" />`. Assert the rendered text contains
    `"Soleur Concierge"` exactly once (e.g., via
    `container.textContent.match(/Soleur Concierge/g)?.length === 1`) AND does NOT match
    `/Concierge\s+Soleur Concierge/`.
  - 3.1.3 Test: render the same bubble with `leaderId="system"`. Assert
    `"System Process"` appears exactly once and does NOT match `/System\s+System Process/`.
  - 3.1.4 Test: render with `leaderId="cmo"` (no `getDisplayName` prop). Assert text
    contains BOTH `"CMO"` AND `"Chief Marketing Officer"` (substring rule must not fire).
  - 3.1.5 Test: render with `leaderId="cmo"` and
    `getDisplayName={() => "CMO Riley"}`. Assert text contains BOTH `"CMO Riley"` AND
    `"Chief Marketing Officer"` (team-name path unaffected).
- 3.2 (GREEN) `apps/web-platform/components/chat/message-bubble.tsx`:
  - 3.2.1 In the header render block (lines ~145-153), gate the `leader.title` span:
    when `leader.title.includes(displayName)`, render `<span>{leader.title}</span>` and skip
    the bare `displayName` span. Otherwise keep the existing two-span shape.
  - 3.2.2 If the substring rule causes unexpected churn (verify by running ALL existing
    `message-bubble*.test.tsx` files), fall back to the
    `leaderId === CC_ROUTER_LEADER_ID || leaderId === "system"` special-case. This is the
    documented acceptable fallback.
- 3.3 Run `bun test apps/web-platform/test/message-bubble-header.test.tsx` AND
  `bun test apps/web-platform/test/message-bubble-retry.test.tsx` AND
  `bun test apps/web-platform/test/message-bubble-memo.test.tsx`. All green.

## Phase 4 — Type-check and full suite

- 4.1 `bun run --cwd apps/web-platform typecheck`. Fix any errors.
- 4.2 `bun run --cwd apps/web-platform test` (full suite). Suite must pass at ≥ pre-PR baseline.

## Phase 5 — Manual verification

- 5.1 Start the kb-concierge panel locally against an attached PDF (the plan's reference
  fixture or the closest equivalent in `knowledge-base/`).
- 5.2 Ask "can you summarize this document?". Confirm a complete summary renders and the
  header shows `Soleur Concierge` exactly once.

## Phase 6 — Compound + ship

- 6.1 Run `skill: soleur:compound` to capture any session learnings.
- 6.2 Run `skill: soleur:ship`. Use `semver:patch` (bug fix).
