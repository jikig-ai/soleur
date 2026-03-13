---
title: "feat: Telegram streamed responses"
type: feat
date: 2026-03-02
version_bump: MINOR
---

# feat: Telegram Streamed Responses

## Overview

Add real-time response streaming to the Telegram bridge. Users will see Claude's text appear progressively instead of waiting for the complete response. Uses `editMessageText` to progressively update the existing "Thinking..." status message with accumulated text.

## Problem Statement

The bridge waits for the complete Claude response before sending it. During generation (10-30+ seconds), users only see "Thinking..." — a poor UX compared to other AI assistants. The Claude CLI already emits incremental `content_block_delta` events via `--output-format stream-json`, but the bridge discards them.

## Non-Goals

- `sendMessageDraft` native streaming (tracked in follow-up issue)
- Streaming media/image responses (text only)
- Streaming in group chats (bridge is private-chat only)
- Custom streaming speed controls
- Markdown rendering during streaming (deferred to final message)
- Tool use streaming indicators (existing `recordToolUse` + status pattern suffices)

## Proposed Solution

### Strategy: Progressive `editMessageText`

1. Add `--include-partial-messages` to CLI spawn args to enable `stream_event` NDJSON lines
2. Repurpose the existing "Thinking..." status message — edit it with accumulated text at ~2.5s intervals
3. Plain text during streaming. Final HTML-formatted message on completion via existing `markdownToHtml` pipeline
4. Split at `MAX_CHUNK_SIZE` threshold when accumulated text approaches Telegram's 4096-char limit

This reuses the battle-tested throttle pattern already in the codebase for status message edits.

### Design Decisions

**D1: CLI flag.** Add `--include-partial-messages` to CLI spawn args. Without this, the CLI never emits `stream_event` NDJSON lines. The `assistant` message still arrives as a separate event for final delivery. **Prerequisite:** Verify the exact event envelope shape by running the CLI with this flag before implementing (open question from SpecFlow).

**D2: Event envelope.** CLI wraps Anthropic events in `{"type": "stream_event", "event": {...}}`. The inner event has `type` (`content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`). Text deltas are at `msg.event.delta.text` when `msg.event.delta.type === "text_delta"`. **Must be verified empirically before coding.**

**D3: Status-to-streaming transition.** Repurpose the "Thinking..." status message — edit it with the first accumulated text. No flicker, no extra message. The `messageId` from `TurnStatus` is reused. **Critical:** When streaming is active, `cleanupTurnStatus()` must NOT call `deleteMessage` — the status message has been repurposed as the streaming message. Null out `turnStatus` and clear the typing timer, but skip the delete.

**D4: `assistant` event deduplication.** When streaming was active: final `editMessageText` on the streaming message with HTML-formatted content. Skip `sendChunked`. The `fullText` for HTML formatting is the last segment's accumulated text only (not the entire response across splits). If the response fit in one message, `fullText` is the complete response. Falls back to plain text if HTML parse fails (existing pattern).

**D5: Split threshold.** Use the existing `MAX_CHUNK_SIZE` constant (4000). When accumulated text reaches this threshold, finalize current message as plain text via `sendMessage`, start a new streaming edit on a fresh message. Earlier split chunks stay plain text — only the last message gets HTML on completion.

**D6: Block type filtering.** Filter `content_block_start` by `content_block.type === "text"` before initializing streaming. Ignore `tool_use` blocks — those are handled by the existing `recordToolUse` path in the `assistant` event. A second `content_block_start` with `type: "text"` (after a tool_use block) must NOT reinitialize StreamState — it should resume accumulation.

**D7: Race condition — first delta before status message resolves.** Guard streaming edits with `messageId !== 0`. If the status message hasn't resolved yet, accumulate deltas but don't flush. The first throttle check after `messageId` is set will flush the accumulated buffer. Reuse the existing `messageId: 0` sentinel pattern.

**D8: Typing indicator lifecycle.** Clear the `typingTimer` when streaming begins — the progressively updating text serves as the activity indicator. The timer is unnecessary overhead during streaming.

## Technical Approach

### Architecture

```
handleCliMessage switch:
  "system"          → existing init logic (unchanged)
  "stream_event"    → NEW: route by msg.event.type
    content_block_start  → init StreamState if text block (and not already active)
    content_block_delta  → accumulate text, throttled editMessageText
    content_block_stop   → no-op (streaming continues across blocks)
    message_delta        → no-op
    message_stop         → no-op
  "assistant"       → MODIFIED: conditional on streaming active
    if streaming: final editMessageText with HTML, skip sendChunked
    else: existing sendChunked path (unchanged)
  "result"          → MODIFIED: cleanup StreamState + existing cleanup
```

### StreamState Type

```typescript
// apps/telegram-bridge/src/types.ts
export interface StreamState {
  chatId: number;
  messageId: number;        // reused from TurnStatus, 0 until resolved
  accumulatedText: string;  // full text accumulated across deltas
  lastUpdateTime: number;   // for Date.now() throttle
}
```

### `editMessageText` Signature Extension

The existing `BotApi.editMessageText` lacks an `other?` parameter needed for `parse_mode: "HTML"` on the final edit. Extend:

```typescript
// apps/telegram-bridge/src/types.ts — update existing signature
editMessageText(
  chatId: number,
  messageId: number,
  text: string,
  other?: Record<string, unknown>,
): Promise<unknown>;
```

Update the grammY adapter in `index.ts` to forward `other`. Update `createMockApi()` in tests.

### Key Files

| File | Changes |
|------|---------|
| `apps/telegram-bridge/src/types.ts` | Add `StreamState`, extend `editMessageText` with `other?` param |
| `apps/telegram-bridge/src/bridge.ts` | Add `stream_event` case, streaming methods, modified `assistant`/`result`/`cleanupTurnStatus` |
| `apps/telegram-bridge/src/index.ts` | Add `--include-partial-messages` to CLI args, update `editMessageText` adapter |
| `apps/telegram-bridge/src/helpers.ts` | No changes (streaming is plain text; existing helpers handle final formatting) |
| `apps/telegram-bridge/test/bridge.test.ts` | New streaming test suite, updated mock for `editMessageText` |

### Implementation Phases

#### Phase 1: Types + CLI Flag + Core Streaming

Add `--include-partial-messages` flag. Define `StreamState`. Extend `editMessageText` signature. Add `stream_event` handling to `handleCliMessage`. Implement delta accumulation with throttled `editMessageText` updates on the repurposed status message.

**Files:** `types.ts`, `index.ts`, `bridge.ts`

**Key logic:**

```
On content_block_start (type: "text", no active streamState):
  streamState = { chatId, messageId: turnStatus.messageId, accumulatedText: "", lastUpdateTime: 0 }
  clear typingTimer

On content_block_delta (text_delta):
  streamState.accumulatedText += delta.text
  if messageId !== 0 AND Date.now() - lastUpdateTime >= STREAM_EDIT_INTERVAL_MS:
    editMessageText(chatId, messageId, accumulatedText)  // plain text, no parse_mode
    lastUpdateTime = Date.now()
  if accumulatedText.length >= MAX_CHUNK_SIZE:
    sendMessage(chatId, accumulatedText)  // finalize as plain text
    start new message for next segment (sendMessage → store new messageId)
    reset accumulatedText

On assistant event (streamState active):
  html = markdownToHtml(accumulatedText)  // last segment only
  editMessageText(chatId, messageId, html, { parse_mode: "HTML" })
    .catch(() => editMessageText(chatId, messageId, accumulatedText))  // plain text fallback
  skip sendChunked for this text
  // NOTE: do NOT call cleanupTurnStatus() — the message is the streaming message

On result event:
  if streamState: cleanupStreamState()  // null streamState, no message deletion
  existing cleanup (unchanged)
```

**`cleanupTurnStatus` modification:** When `streamState` is active, skip `deleteMessage` but still null the status and clear the timer.

**Acceptance:**
- Text appears progressively in Telegram
- Updates throttled at ~2.5s intervals
- Final message is HTML-formatted
- No duplicate messages
- "Thinking..." transitions to streaming text without flicker

#### Phase 2: Tests

Add streaming test suite following existing patterns (mock BotApi, `cliMsg` helper, async settlement).

**Files:** `test/bridge.test.ts`

**Test scenarios:**

1. **Happy path:** `stream_event` deltas → progressive edits → `assistant` → final HTML edit
2. **4096 split:** Accumulated text exceeds `MAX_CHUNK_SIZE` → split into two messages
3. **Race condition:** First delta arrives before status message resolves (messageId=0) → buffered, flushed later
4. **CLI crash mid-stream:** Process exit during streaming → StreamState cleaned up
5. **No deltas:** `content_block_start` + `content_block_stop` with zero deltas → no edit, no error
6. **Interleaved blocks:** Text → tool_use → text in single turn → streaming resumes without reinit
7. **Turn watchdog during streaming:** 10-minute timeout fires → StreamState cleaned up
8. **HTML parse failure on final edit:** Falls back to plain text

## Acceptance Criteria

- [ ] Text appears progressively in Telegram within 2.5s of CLI delta events
- [ ] Final message is HTML-formatted via existing `markdownToHtml` pipeline
- [ ] Responses >4096 chars split at `MAX_CHUNK_SIZE` threshold into multiple messages
- [ ] "Thinking..." status transitions to streaming without flicker (no delete + send)
- [ ] No duplicate message delivery from `assistant` handler
- [ ] `cleanupTurnStatus` skips `deleteMessage` when streaming was active
- [ ] StreamState cleaned up on `result`, errors, and CLI crash
- [ ] All existing tests pass unchanged
- [ ] 8 new streaming tests covering lifecycle, splits, race conditions, edge cases
- [ ] Typing timer cleared when streaming begins

## Test Scenarios

- Given a normal response, when CLI emits text deltas, then Telegram message updates progressively via `editMessageText`
- Given accumulated text reaches `MAX_CHUNK_SIZE`, when next delta arrives, then current message is finalized and new stream starts
- Given status message hasn't resolved (messageId=0), when first delta arrives, then deltas are buffered until messageId is available
- Given streaming is active, when `assistant` event arrives, then final message is HTML-formatted (not duplicate)
- Given final HTML edit fails to parse, when `editMessageText` throws, then falls back to plain text edit
- Given CLI crashes mid-stream, when process exit fires, then StreamState is cleaned up
- Given text block followed by tool_use then text block, when second text block starts, then streaming resumes (no reinit)
- Given streaming is active for 10+ minutes, when turn watchdog fires, then StreamState is cleaned up

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Telegram rate limits on `editMessageText` (~20/min) | Medium | 2.5s throttle interval = 24/min max; splitting reduces total edits for long responses |
| Partial markdown at split boundaries | Medium | Split chunks stay plain text; only final message gets HTML |
| Delta-before-status-resolved race | Medium | Buffer + `messageId: 0` sentinel guard |
| `cleanupTurnStatus` deleting repurposed message | High | Explicit guard: skip `deleteMessage` when `streamState` active |
| Multi-byte characters exceeding 4096 bytes under JS `.length` | Low | Known limitation, same as existing `chunkMessage` |

## Rollback

Revert the commit. The change is additive — `stream_event` handling and the `--include-partial-messages` flag. Reverting restores the existing behavior where deltas are logged and discarded.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-02-telegram-streaming-brainstorm.md`
- Spec: `knowledge-base/specs/feat-telegram-streaming/spec.md`
- Issue: #372
- Follow-up: `sendMessageDraft` native streaming (issue TBD)
- Bridge source: `apps/telegram-bridge/src/bridge.ts`
- Async lifecycle learning: `knowledge-base/learnings/runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md`
- DI architecture learning: `knowledge-base/learnings/implementation-patterns/2026-02-11-testability-refactoring-dependency-injection.md`
- Telegram Bot API: https://core.telegram.org/bots/api
- grammY docs: https://grammy.dev/ref/core/api
