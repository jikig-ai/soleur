---
title: "feat: Telegram streamed responses"
type: feat
date: 2026-03-02
---

# feat: Telegram Streamed Responses

## Overview

Add real-time response streaming to the Telegram bridge. Users will see Claude's text appear progressively instead of waiting for the complete response. Uses Telegram's native `sendMessageDraft` API with `editMessageText` fallback.

## Problem Statement

The bridge waits for the complete Claude response before sending it. During generation (10-30+ seconds), users only see "Thinking..." — a poor UX compared to other AI assistants. The Claude CLI already emits incremental `content_block_delta` events via `--output-format stream-json`, but the bridge discards them.

## Proposed Solution

### Strategy: Native-first with progressive fallback

1. **Primary:** `sendMessageDraft` for smooth animated streaming (Bot API 9.5, grammY v1.40.0 native support)
2. **Fallback:** `editMessageText` with 2-3s throttled updates (battle-tested pattern already in codebase)
3. **Detection:** Try `sendMessageDraft` on first turn. Cache result per session. Only `400`-class errors with draft-specific descriptions (`TEXTDRAFT_PEER_INVALID`, `PEER_ID_INVALID`) trigger permanent fallback. Transient errors (429, network) are retried.
4. **Formatting:** Plain text during streaming. Final HTML-formatted message on completion.

### Critical Design Decisions (from SpecFlow analysis)

**D1: CLI flag.** Add `--include-partial-messages` to CLI spawn args. Without this, the CLI never emits `stream_event` NDJSON lines. The `assistant` message still arrives as a separate event for final delivery.

**D2: Event envelope.** CLI wraps Anthropic events in `{"type": "stream_event", "event": {...}}`. The inner event has `type` (`content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`). Text deltas are at `msg.event.delta.text` when `msg.event.delta.type === "text_delta"`.

**D3: Status-to-streaming transition.**
- **Fallback mode:** Repurpose the "Thinking..." status message — edit it with the first accumulated text. No flicker, no extra message.
- **Native mode:** Delete the status message and begin `sendMessageDraft`. The draft appears as a typing indicator that evolves into text.

**D4: `assistant` event deduplication.** When streaming was active:
- **Fallback mode:** Final `editMessageText` on the last streaming message with HTML-formatted content. Skip `sendChunked`.
- **Native mode:** `sendMessage` with HTML-formatted content (draft is not a real message). Skip `sendChunked` for the first chunk.
- Both modes: If the response was split (>4096), only the last message gets HTML formatting. Earlier split chunks stay plain text.

**D5: Split threshold.** Use 3800 characters (matches spirit of existing `MAX_CHUNK_SIZE = 4000`, leaves room for HTML overhead on final format). Finalize current message as plain text via `sendMessage`, start new streaming message for remainder.

**D6: Draft ID strategy.** Monotonically increasing counter per session, starting at 1. Increment for each new streaming message (including after 4096 splits).

**D7: `sendMessageDraft` throttle.** 500ms interval via `Date.now()` time-check (same pattern as status edits, but faster since drafts are lighter).

**D8: Tool use pause.** Append `"\n\n⚙️ Using [tool]..."` to the streamed text in the same message. Remove the indicator when text streaming resumes by editing with the clean accumulated text. No separate status message.

**D9: Block type filtering.** Filter `content_block_start` by `content_block.type === "text"` before initializing streaming. Ignore `tool_use` blocks for streaming — those are handled separately via the existing `recordToolUse` path in the `assistant` event.

**D10: Race condition — first delta before status message resolves.** Guard streaming operations with `streamState.messageId !== 0` (fallback) or a `draftStarted` boolean (native). If the status message hasn't resolved yet, buffer deltas and flush on resolution. Reuse the existing `messageId: 0` sentinel pattern.

## Technical Approach

### Architecture

```
handleCliMessage switch:
  "system"          → existing init logic (unchanged)
  "stream_event"    → NEW: route by msg.event.type
    content_block_start  → init StreamState if text block
    content_block_delta  → accumulate text, throttled Telegram update
    content_block_stop   → mark block complete
    message_delta        → no-op (stop_reason info)
    message_stop         → no-op
  "assistant"       → MODIFIED: conditional on streaming active
    if streaming: final edit/send with HTML, skip sendChunked for streamed portion
    else: existing sendChunked path (unchanged)
  "result"          → MODIFIED: cleanup StreamState + existing cleanup
```

### StreamState Type

```typescript
// apps/telegram-bridge/src/types.ts
export interface StreamState {
  chatId: number;
  strategy: "native" | "fallback" | "detecting";
  messageId: number;        // 0 until sendMessage resolves (fallback)
  draftId: number;          // current draft_id (native)
  accumulatedText: string;  // full text accumulated across deltas
  lastUpdateTime: number;   // for Date.now() throttle
  blockIndex: number;       // current content_block index
  splitMessages: number[];  // message_ids of finalized split chunks
  paused: boolean;          // true during tool use
}
```

### BotApi Extension

```typescript
// apps/telegram-bridge/src/types.ts — add to BotApi
sendMessageDraft(
  chatId: number,
  draftId: number,
  text: string,
  other?: Record<string, unknown>,
): Promise<true>;
```

### BridgeConfig Extension

```typescript
// apps/telegram-bridge/src/types.ts — add to BridgeConfig
streamDraftIntervalMs?: number;  // default 500
streamEditIntervalMs?: number;   // default 2500
streamSplitThreshold?: number;   // default 3800
```

### Key Files

| File | Changes |
|------|---------|
| `apps/telegram-bridge/src/types.ts` | Add `StreamState`, extend `BotApi` + `BridgeConfig` |
| `apps/telegram-bridge/src/bridge.ts` | Add `stream_event` case, streaming methods, modified `assistant`/`result` handlers |
| `apps/telegram-bridge/src/index.ts` | Add `--include-partial-messages` to CLI args, add `sendMessageDraft` to BotApi adapter |
| `apps/telegram-bridge/src/helpers.ts` | No changes expected (streaming is plain text; existing helpers handle final formatting) |
| `apps/telegram-bridge/test/bridge.test.ts` | New streaming test suite |

### Implementation Phases

#### Phase 1: Foundation — Types + CLI Flag + BotApi

Add the `--include-partial-messages` flag to CLI spawn, define `StreamState` and `BridgeConfig` extensions, extend `BotApi` interface and adapter.

**Files:** `types.ts`, `index.ts`

**Acceptance:**
- CLI emits `stream_event` lines (observable in logs)
- `sendMessageDraft` available on `BotApi`
- Types compile cleanly

#### Phase 2: Core Streaming — Delta Accumulation + Throttled Updates

Add `stream_event` handling to `handleCliMessage`. Implement `initStreamState`, `handleTextDelta`, `flushStreamUpdate`, `finalizeStreamMessage` methods on Bridge.

**Files:** `bridge.ts`

**Key logic:**

```
initStreamState(chatId):
  set strategy = "detecting"
  try sendMessageDraft → strategy = "native"
  catch → strategy = "fallback", edit status message instead

handleTextDelta(text):
  accumulatedText += text
  if Date.now() - lastUpdateTime >= interval:
    if strategy === "native": sendMessageDraft(chatId, draftId, accumulatedText)
    if strategy === "fallback": editMessageText(chatId, messageId, accumulatedText)
    lastUpdateTime = Date.now()
  if accumulatedText.length >= splitThreshold:
    finalizeStreamMessage() → sendMessage, reset accumulator, increment draftId

finalizeStreamMessage():
  send accumulatedText as plain text via sendMessage
  store message_id in splitMessages
  reset accumulatedText, increment draftId or get new messageId
```

**Acceptance:**
- Text appears progressively in Telegram
- Updates throttled at configured interval
- `sendMessageDraft` detection works and caches per session

#### Phase 3: Modified Assistant/Result Handlers

Modify `assistant` event handler to detect active streaming and skip `sendChunked` for already-delivered text. Add HTML-formatted final message. Modify `result` handler to clean up `StreamState`.

**Files:** `bridge.ts`

**Key logic:**

```
handleAssistant (modified):
  if streamState exists:
    html = markdownToHtml(fullText)
    if strategy === "fallback":
      editMessageText(chatId, lastMessageId, html, {parse_mode: "HTML"})
    if strategy === "native":
      sendMessage(chatId, html, {parse_mode: "HTML"})
    cleanupStreamState()
  else:
    existing sendChunked path (unchanged)

handleResult (modified):
  if streamState exists: cleanupStreamState()
  existing cleanup (unchanged)
```

**Acceptance:**
- Final message is HTML-formatted
- No duplicate messages
- StreamState cleaned up on turn completion

#### Phase 4: 4096-Char Splitting + Tool Use Pause/Resume

Implement split-at-threshold logic and tool use pause/resume with inline indicator.

**Files:** `bridge.ts`

**Key logic:**

```
handleTextDelta (extended):
  if accumulatedText.length >= 3800:
    finalizeStreamMessage()  // sends plain text, starts new stream

handleToolUse:
  streamState.paused = true
  append "\n\n⚙️ Using [tool]..." to current stream message

handleTextResume:
  streamState.paused = false
  edit message to remove tool indicator, continue accumulating
```

**Acceptance:**
- Responses >4096 chars split into multiple messages during streaming
- Tool indicator appears during tool execution
- Streaming resumes after tool completes

#### Phase 5: Tests

Add streaming test suite following existing patterns (mock BotApi, `cliMsg` helper, async settlement).

**Files:** `test/bridge.test.ts`

**Test scenarios:**

1. **Happy path native:** `stream_event` → deltas → `assistant` → final HTML
2. **Happy path fallback:** `sendMessageDraft` throws → fallback to `editMessageText`
3. **Detection caching:** Second turn skips detection, uses cached strategy
4. **4096 split:** Accumulated text exceeds threshold → split into two messages
5. **Tool use pause/resume:** Text deltas → tool block → text resumes
6. **Race condition:** First delta arrives before status message resolves
7. **CLI crash mid-stream:** Process exit during streaming → cleanup
8. **No deltas:** `content_block_start` + `content_block_stop` with zero deltas
9. **Interleaved blocks:** Text → tool → text in single turn
10. **Fallback 429:** Transient rate limit does NOT trigger permanent fallback
11. **Turn watchdog during streaming:** 10-minute timeout fires → cleanup

## Acceptance Criteria

- [ ] Text appears progressively in Telegram within 2s of CLI delta events
- [ ] `sendMessageDraft` used when available, `editMessageText` as fallback
- [ ] Detection cached per session; transient errors don't trigger permanent fallback
- [ ] Final message is HTML-formatted via existing `markdownToHtml` pipeline
- [ ] Responses >4096 chars split at 3800-char threshold into multiple messages
- [ ] Tool use shows inline `⚙️ Using [tool]...` indicator, removed on resume
- [ ] "Thinking..." status transitions to streaming without flicker
- [ ] No duplicate message delivery from `assistant` handler
- [ ] StreamState cleaned up on `result`, errors, and CLI crash
- [ ] All existing 59 tests pass unchanged
- [ ] 11 new streaming tests covering lifecycle, fallback, splits, tool pause, edge cases

## Test Scenarios

- Given a normal response, when CLI emits text deltas, then Telegram message updates progressively
- Given `sendMessageDraft` returns `TEXTDRAFT_PEER_INVALID`, when first delta arrives, then bridge falls back to `editMessageText` and caches for session
- Given a 429 rate limit on `sendMessageDraft`, when first delta arrives, then bridge retries (does NOT permanently fall back)
- Given accumulated text reaches 3800 chars, when next delta arrives, then current message is finalized and new stream starts
- Given text block followed by tool_use block, when tool block starts, then stream message shows tool indicator
- Given streaming is active, when `assistant` event arrives, then final message is HTML-formatted (not duplicate)
- Given CLI crashes mid-stream, when process exit fires, then StreamState is cleaned up
- Given status message hasn't resolved, when first delta arrives, then deltas are buffered until messageId is available

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `sendMessageDraft` unreliable in private chats | High | Automatic fallback + detection caching |
| Partial markdown at split boundaries | Medium | Split chunks stay plain text; only final chunk gets HTML |
| Telegram rate limits on `editMessageText` | Medium | 2.5s throttle in fallback; split reduces total edits |
| Delta-before-status-resolved race | Medium | Buffer + messageId sentinel guard |
| Draft doesn't auto-dismiss on `sendMessage` | Low | Empirical testing; worst case is brief visual overlap |

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-02-telegram-streaming-brainstorm.md`
- Spec: `knowledge-base/specs/feat-telegram-streaming/spec.md`
- Issue: #372
- Bridge source: `apps/telegram-bridge/src/bridge.ts`
- Async lifecycle learning: `knowledge-base/learnings/runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md`
- DI architecture learning: `knowledge-base/learnings/implementation-patterns/2026-02-11-testability-refactoring-dependency-injection.md`
- Telegram Bot API `sendMessageDraft`: https://core.telegram.org/bots/api#sendmessagedraft
- grammY docs: https://grammy.dev/ref/core/api
