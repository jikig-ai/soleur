# Spec: Telegram Streamed Responses

**Issue:** #372
**Date:** 2026-03-02
**Status:** Draft

## Problem Statement

The Telegram bridge currently waits for the complete Claude response before sending it to the user. During generation (which can take 10-30+ seconds), users only see a "Thinking..." status message. This creates a poor UX compared to ChatGPT and other AI assistants that stream text progressively.

The Claude CLI already emits incremental `content_block_delta` events, but the bridge discards them.

## Goals

- G1: Stream Claude responses to Telegram users in real-time as text is generated
- G2: Use Telegram's native `sendMessageDraft` API as the primary streaming method
- G3: Fall back gracefully to `editMessageText` progressive updates when native streaming is unavailable
- G4: Maintain proper formatting — plain text during stream, HTML-formatted final message
- G5: Handle long responses (>4096 chars) by splitting into multiple streaming messages

## Non-Goals

- Streaming media/image responses (text only)
- Streaming in group chats (bridge is private-chat only)
- Custom streaming speed controls
- Markdown rendering during streaming (deferred to final message)

## Functional Requirements

- **FR1:** Handle `content_block_start`, `content_block_delta`, and `content_block_stop` CLI events in `handleCliMessage`
- **FR2:** Accumulate text deltas and update the Telegram message progressively
- **FR3:** Use `sendMessageDraft` as the primary streaming method; detect support on first use and cache result per session
- **FR4:** Fall back to `editMessageText` with 2-3s throttle when `sendMessageDraft` errors
- **FR5:** Send plain text during streaming; replace with HTML-formatted message on completion
- **FR6:** When accumulated text approaches 4096 chars, finalize current message and start a new streaming message
- **FR7:** Pause text streaming during tool use; show tool status indicator; resume when text continues
- **FR8:** Clean up streaming state on turn completion (`result` event) and on errors

## Technical Requirements

- **TR1:** New `StreamState` type separate from `TurnStatus` to avoid state overload
- **TR2:** Extend `BotApi` interface with `sendMessageDraft` method (or use raw API call)
- **TR3:** Follow existing async lifecycle patterns: `Date.now()` throttle, readiness guards, state null-before-cleanup
- **TR4:** Transition from "Thinking..." status to streaming without message deletion flicker
- **TR5:** Test coverage for: streaming lifecycle, fallback detection, 4096-char splitting, tool use pause/resume, error recovery
- **TR6:** No regression in existing functionality (commands, error handling, health endpoint)

## Architecture

### Key Files

| File | Changes |
|------|---------|
| `apps/telegram-bridge/src/types.ts` | Add `StreamState` type, extend `BotApi` with `sendMessageDraft` |
| `apps/telegram-bridge/src/bridge.ts` | Add delta handling cases, streaming logic, fallback detection |
| `apps/telegram-bridge/src/helpers.ts` | Potential new helpers for stream text accumulation |
| `apps/telegram-bridge/test/bridge.test.ts` | Streaming lifecycle tests |

### Data Flow

```
CLI stdout → NDJSON parser → handleCliMessage
  → content_block_start: initialize StreamState
  → content_block_delta: accumulate text, throttled update to Telegram
  → content_block_stop: finalize block
  → assistant (complete): send final HTML-formatted message
  → result: cleanup streaming state
```

### Streaming Strategy Detection

```
First turn:
  1. Try sendMessageDraft()
  2. If success → cache "native" for session
  3. If error → cache "fallback" for session, use editMessageText

Subsequent turns:
  Use cached strategy without re-detection
```

## Acceptance Criteria

- [ ] Text appears progressively in Telegram within 2s of CLI delta events
- [ ] `sendMessageDraft` used when available, `editMessageText` as fallback
- [ ] Final message is HTML-formatted via existing pipeline
- [ ] Responses >4096 chars split into multiple messages during streaming
- [ ] Tool use shows status indicator, streaming resumes after
- [ ] All existing tests pass
- [ ] New tests cover streaming lifecycle, fallback, and edge cases
