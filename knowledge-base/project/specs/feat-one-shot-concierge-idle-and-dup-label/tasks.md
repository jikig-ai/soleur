# Tasks — feat-one-shot-concierge-idle-and-dup-label

Plan: `knowledge-base/project/plans/2026-05-05-fix-concierge-idle-runaway-and-duplicate-label-plan.md`

## Phase 1 — Setup

- 1.1 Verify the worktree branch matches the feat name and the plan file is committed before
  starting the TDD cycle.

## Phase 2 — Bug 1: Runaway timer relaxation (TDD)

- 2.1 (RED) Update `apps/web-platform/test/soleur-go-runner.test.ts`:
  - 2.1.1 Update the existing `DEFAULT_WALL_CLOCK_TRIGGER_MS` / 30s assertion to 90s.
  - 2.1.2 Add a test: emit one `tool_use`, advance virtual clock 25s, emit a second `tool_use`,
    advance another 70s (total 95s from first), assert `runner_runaway` does NOT fire.
  - 2.1.3 Add a test: emit one `tool_use`, advance virtual clock 25s, emit an assistant `text`
    block, advance another 70s, assert `runner_runaway` does NOT fire.
  - 2.1.4 Add a test: emit one `tool_use`, advance virtual clock 95s with no further blocks,
    assert `runner_runaway` fires with `elapsedMs >= 90_000`.
- 2.2 (GREEN) `apps/web-platform/server/soleur-go-runner.ts`:
  - 2.2.1 Change `DEFAULT_WALL_CLOCK_TRIGGER_MS = 30 * 1000` to `90 * 1000`.
  - 2.2.2 In `handleAssistantMessage`, after every `text` and `tool_use` block, when
    `state.firstToolUseAt !== null` and `!state.awaitingUser`, call `armRunaway(state)` to
    reset the window. (Move the existing first-tool-use arm to the same path or keep it
    + add the re-arm — implementer's choice as long as the four tests pass.)
  - 2.2.3 Update the comment block (~798-803) describing the wall-clock semantics from
    "FIRST tool_use" to "any assistant block (text or tool_use) resets the clock".
- 2.3 Run `bun run --cwd apps/web-platform test soleur-go-runner.test.ts`. Confirm green.

## Phase 3 — Bug 2: Header label deduplication (TDD)

- 3.1 (RED) Add or extend a message-bubble test:
  - 3.1.1 Render `<MessageBubble role="assistant" leaderId="cc_router" showFullTitle messageState="done" content="…" />`. Assert the header's text content equals `"Soleur Concierge"`
    exactly once and does NOT contain `"Concierge   Soleur Concierge"` or a leading bare
    `"Concierge"` token followed by whitespace.
  - 3.1.2 Render the same bubble with `leaderId="cmo"` (or any non-cc leader where name and
    title differ). Assert the header contains BOTH the team-name token AND `leader.title` —
    regression guard against an over-broad duplicate-suppression rule.
- 3.2 (GREEN) `apps/web-platform/components/chat/message-bubble.tsx`:
  - 3.2.1 Import `CC_ROUTER_LEADER_ID` from `@/lib/cc-router-id`.
  - 3.2.2 In the header render block (lines ~145-153), special-case
    `leaderId === CC_ROUTER_LEADER_ID`: render `leader.title` only and skip the bare
    `displayName` span. Other leaders unchanged.
- 3.3 Run the message-bubble test. Confirm green.

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
