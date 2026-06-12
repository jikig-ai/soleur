---
title: "Tasks — fix: forward tool_progress to client on cc surface"
issue: 5214
branch: feat-one-shot-fwd-tool-progress-cc-surface-5214
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-12-fix-forward-tool-progress-cc-surface-plan.md
created: 2026-06-12
---

# Tasks — forward `tool_progress` to client on cc surface (#5214)

Derived from `knowledge-base/project/plans/2026-06-12-fix-forward-tool-progress-cc-surface-plan.md`.
Two-layer fix (runner emits `onToolProgress` DispatchEvent → cc-dispatcher forwards a
`tool_progress` WS message), mirroring `agent-runner.ts:1889-1948`. Downstream consumer
(`chat-state-machine.ts:490`, `ws-constants.ts`, WS variant) is already complete — DO NOT edit.

## Phase 0 — Preconditions (verify, no edits)

- [x] 0.1 Confirm `apps/web-platform/lib/chat-state-machine.ts:490` (`case "tool_progress"`)
  resets the watchdog + clears `retrying` + has the #2886 no-chip guard — and stays UNCHANGED.
- [x] 0.2 Confirm the `tool_progress` WS variant exists: `lib/types.ts:319`,
  `lib/ws-zod-schemas.ts:280`, `lib/ws-known-types.ts:43`, `lib/ws-client.ts:688`. No edit.
- [x] 0.3 Confirm `includePartialMessages: true` at `agent-runner-query-options.ts:160` and
  that cc's `realSdkQueryFactory` (`cc-dispatcher.ts:~1811`) consumes `buildAgentQueryOptions`.
- [x] 0.4 Read the precedent forward `agent-runner.ts:1889-1948` (shape-guard, debounce,
  `buildToolLabel` routing) and the existing cc `tool_use` forward (`cc-dispatcher.ts:~2512`).

## Phase 1 — RED tests (write first; must fail)

- [x] 1.1 Create `apps/web-platform/test/cc-dispatcher-tool-progress-forwarding.test.ts`:
  - [x] 1.1.1 Test #1 — runner emits `onToolProgress` (`makeRecordingEvents` +
    `makeToolProgress("tu-1", 5)`); assert recorded `{ toolUseId, elapsedSeconds, toolName: "Read" }`.
  - [x] 1.1.2 Test #2 — dispatcher forwards a `tool_progress` WS message via harness +
    `mockSendToClient`; assert `{ type: "tool_progress", leaderId: "cc_router", toolUseId,
    toolName: <human label, !== "Read">, elapsedSeconds }`. (Load-bearing RED for the bug.)
  - [x] 1.1.3 Test #3 — debounce ≤1/5s per `toolUseId`; drive the clock via
    `vi.setSystemTime()` per heartbeat (NOT `advanceTimersByTime` — debounce reads `Date.now()`;
    precedent `tool-progress-forwarding.test.ts:204-209`); assert 2 forwards across t=0/2s/6s.
  - [x] 1.1.4 Test #4 — malformed `tool_progress` (missing `tool_use_id`) as the SOLE
    `tool_progress` in the test; assert no forward + `reportSilentFallback` `op:
    "tool-progress-shape"` + POSITIVE CONTROL `armRunaway` fired (no `runner_runaway` after
    the idle window; precedent `soleur-go-runner-tool-result-idle-reset.test.ts:132-140`).
- [x] 1.2 Create `apps/web-platform/test/cc-soleur-go-tool-progress-no-terminal-error.test.tsx`
  (consumer-contract guards — GREEN pre-fix; lock the reducer the forward feeds):
  - [x] 1.2.1 Test #5 — >90s tool with `tool_progress` does NOT flip `cc_router` to
    `state: "error"` and does NOT evict from `activeStreams`.
  - [x] 1.2.2 Test #6 — first-timeout `retrying: true` is cleared by a `tool_progress`
    event (do NOT duplicate the chip-no-spawn assertion already at
    `cc-soleur-go-end-to-end-render.test.tsx:176-187`).
  - [x] 1.2.3 Test #7 — control: a tool emitting NO `tool_progress` STILL flips to terminal
    error after two timeouts (defense-pair).
- [x] 1.3 Run both files; confirm server #1-#4 are RED (fail before the fix).

## Phase 2 — Implementation (GREEN)

- [x] 2.1 `soleur-go-runner.ts` — add optional `onToolProgress?: (block: { toolUseId:
  string; toolName: string; elapsedSeconds: number }) => void;` to `DispatchEvents`
  (~798-866) with JSDoc (when it fires, why optional, fire-and-forget, the #2138 raw-name
  note, AND that it fires at SDK cadence so consumers MUST debounce).
- [x] 2.2 `soleur-go-runner.ts:2170` `tool_progress` branch — AFTER the existing
  `armRunaway`, shape-guard `tool_use_id`/`tool_name`/`elapsed_time_seconds` (mirror
  `agent-runner.ts:1901-1927`; on mismatch `reportSilentFallback({ feature:
  "soleur-go-runner", op: "tool-progress-shape" })` and skip the emit — NOT the re-arm),
  then invoke `state.events.onToolProgress?.(...)` in `try/catch` →
  `reportSilentFallback({ op: "onToolProgress" })`. Update the "reads NO fields" comment.
- [x] 2.3 `tool-labels.ts` — add `export function buildToolProgressWSMessage(args: {
  toolName; elapsedSeconds; toolUseId; workspacePath; leaderId })` returning
  `{ type: "tool_progress", leaderId, toolUseId, toolName: buildToolLabel(toolName,
  undefined, workspacePath), elapsedSeconds }`; JSDoc cites #3235 + the #2138 invariant.
- [x] 2.4 `cc-dispatcher.ts` — import `buildToolProgressWSMessage`; declare per-dispatch
  `const TOOL_PROGRESS_DEBOUNCE_MS = 5_000;` + `const toolProgressLastSentAt = new
  Map<string, number>();` near the `events` object (~2448).
- [x] 2.5 `cc-dispatcher.ts` — add `onToolProgress` to the `events: DispatchEvents` object:
  debounce per `toolUseId` (first always forwards; subsequent wait 5s), then
  `sendToClient(userId, buildToolProgressWSMessage({ toolName, elapsedSeconds, toolUseId,
  workspacePath, leaderId: CC_ROUTER_LEADER_ID }))`. One-line comment: NO debug-event emit
  for `tool_progress` (parity with agent-runner; debug panel has no `tool_progress` kind).
- [x] 2.6 Run both new test files until green.

## Phase 3 — Verification

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/cc-dispatcher-tool-progress-forwarding.test.ts
  test/cc-soleur-go-tool-progress-no-terminal-error.test.ts` — green.
- [x] 3.3 Regression: `./node_modules/.bin/vitest run test/tool-progress-forwarding.test.ts
  test/chat-state-machine.test.ts test/cc-soleur-go-end-to-end-render.test.tsx` — green.
- [x] 3.4 `git diff --stat` confirms `chat-state-machine.ts` and `ws-constants.ts` are
  UNCHANGED (AC10).
- [x] 3.5 `git grep -n "onToolProgress" apps/web-platform/` — only the runner (def+invoke)
  and cc-dispatcher (wiring) reference it; agent-runner NOT touched.
- [x] 3.6 Walk the Acceptance Criteria (AC1-AC13) in the plan; check each off.

## Phase 4 — Ship

- [x] 4.1 PR body uses `Closes #5214` (AC13).
- [x] 4.2 No post-merge operator steps (pure code change; container restarts on merge via
  `web-platform-release.yml`).
