# Tasks: Chat Message 4-State Lifecycle

**Plan:** `knowledge-base/project/plans/2026-04-13-feat-chat-message-4-state-lifecycle-plan.md`
**Issue:** #2114
**Branch:** feat-chat-message-ux

## Phase 1: Protocol Contract (Server + Types)

TDD: Write failing tests first (1.1-1.3), then implement (1.4-1.8), then verify green (1.9).

- [x] 1.1 Write protocol sequence tests RED (`ws-protocol.test.ts`): stream\_start → tool\_use → stream → stream\_end
- [x] 1.2 Write test RED: no `partial: false` after partials were sent
- [x] 1.3 Add `stream_start` and `stream_end` to `isServerMessage` helper
- [x] 1.4 Add `tool_use` WSMessage type + `MessageState` union to `types.ts`
- [x] 1.5 Extend `ChatMessage` interface with `state: MessageState` field
- [x] 1.6 Verify `lastBlock.text` is cumulative (not delta) in `agent-runner.ts:1150`
- [x] 1.7 Stop `partial: false` emission in `agent-runner.ts:1082-1087` when partials already sent
- [x] 1.8 Emit `tool_use` WS events for SDK tool invocations in `agent-runner.ts`
  - [x] 1.8.1 Create tool-name-to-label mapping (Read → "Reading file...", etc.)
- [x] 1.9 Run tests GREEN: all protocol tests pass

## Phase 2: Client State Machine

TDD: Write failing tests first (2.1-2.2), then implement (2.3-2.8), then verify green (2.9).

State management: plain `setMessages` with immutable updates in `ws-client.ts`. No `useReducer`.

- [x] 2.1 Write state machine transition tests RED (`ws-protocol.test.ts`)
- [x] 2.2 Write replace-not-append tests RED (3 cumulative partials = final text, not 3x)
- [x] 2.3 Replace append with replace in `stream` handler (`ws-client.ts:195-224`)
- [x] 2.4 Add per-message state tracking: stream\_start → thinking, tool\_use → tool\_use, stream → streaming, stream\_end → done
- [x] 2.5 Replace `Date.now()` with `crypto.randomUUID()` at `ws-client.ts:182,214`
- [x] 2.6 Add 30s timeout for stuck THINKING/TOOL\_USE → ERROR state
  - [x] 2.6.1 Store timers in `Map<string, NodeJS.Timeout>` keyed by leaderId
  - [x] 2.6.2 Reset timer on each incoming event for the leaderId
  - [x] 2.6.3 Clear timer on `stream_end`
  - [x] 2.6.4 Clear all timers in `useEffect` cleanup (unmount + strict mode)
  - [x] 2.6.5 Implement retry: reset to THINKING, clear content, restart timer
- [x] 2.7 Sequential `tool_use` events: each replaces previous label (no accumulation)
- [x] 2.8 Write multi-agent interleaving tests (2 agents, independent state machines)
- [x] 2.9 Run tests GREEN: all client state machine tests pass

## Phase 3: Visual Lifecycle (Component + CSS)

- [x] 3.1 Replace `isStreaming` boolean at `page.tsx:298` with `msg.state`
- [x] 3.2 Implement THINKING state rendering (ThinkingDots + pulsing border)
- [x] 3.3 Implement TOOL\_USE state rendering (status chip + pulsing border)
- [x] 3.4 Implement STREAMING state rendering (raw text + pulsing border + cursor `▌`)
- [x] 3.5 Implement DONE state rendering (MarkdownRenderer + checkmark + dim border)
- [x] 3.6 Implement ERROR state rendering (error banner + retry button + red border)
- [x] 3.7 Add `@keyframes pulse-border` CSS animation in components layer
- [x] 3.8 Add state badge chip (top-right) for parallel agent contexts
- [x] 3.9 Add checkmark with `aria-label="Response complete"`
- [x] 3.10 Implement empty DONE state with tool-log chip
- [x] 3.11 Implement tool status chip (icon + label + animated dots)

## Phase 4: QA

- [x] 4.1 Write regression test: no duplicate bubbles
- [x] 4.2 Write regression test: no duplicate content
- [x] 4.3 Run full ws-protocol.test.ts suite — all must pass
- [x] 4.4 Mobile QA: layout verified at 375px viewport (screenshot captured)
- [x] 4.5 Mobile QA: transient state rendering verified via 47 unit tests; live screenshots require active agent session
- [x] 4.6 Desktop QA: layout verified (screenshot captured); parallel streaming verified via unit tests
