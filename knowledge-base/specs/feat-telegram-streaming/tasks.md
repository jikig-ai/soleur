# Tasks: Telegram Streamed Responses

**Plan:** `knowledge-base/plans/2026-03-02-feat-telegram-streamed-responses-plan.md`
**Issue:** #372
**Branch:** feat-telegram-streaming

## Phase 1: Foundation

### 1.1 Define StreamState type and extend BridgeConfig
- [ ] Add `StreamState` interface to `apps/telegram-bridge/src/types.ts`
- [ ] Add `streamDraftIntervalMs`, `streamEditIntervalMs`, `streamSplitThreshold` to `BridgeConfig`
- [ ] Verify types compile: `bun run check` or `bunx tsc --noEmit`

### 1.2 Extend BotApi interface with sendMessageDraft
- [ ] Add `sendMessageDraft(chatId, draftId, text, other?)` to `BotApi` in `types.ts`
- [ ] Add adapter implementation in `index.ts` wrapping `bot.api.sendMessageDraft`
- [ ] Add `sendMessageDraft` mock to `createMockApi()` in `test/bridge.test.ts`

### 1.3 Add --include-partial-messages to CLI spawn
- [ ] Add `"--include-partial-messages"` to `cliArgs` array in `index.ts`
- [ ] Verify CLI emits `stream_event` NDJSON lines in logs

## Phase 2: Core Streaming

### 2.1 Add stream_event routing in handleCliMessage
- [ ] Add `"stream_event"` case to the switch in `handleCliMessage`
- [ ] Route inner `msg.event.type` to appropriate handlers:
  - `content_block_start` (text blocks only) → `initStreamState`
  - `content_block_delta` (text_delta only) → `handleTextDelta`
  - `content_block_stop` → mark block complete
  - `message_delta`, `message_stop` → no-op

### 2.2 Implement initStreamState
- [ ] Create `initStreamState(chatId)` method on Bridge
- [ ] Set strategy to "detecting"
- [ ] Try `sendMessageDraft` — on success set strategy to "native"
- [ ] On draft-specific error (400 with `TEXTDRAFT_PEER_INVALID`), set strategy to "fallback"
- [ ] In fallback: repurpose status message (edit "Thinking..." with first text)
- [ ] Cache detected strategy on Bridge instance for subsequent turns

### 2.3 Implement handleTextDelta + flushStreamUpdate
- [ ] Accumulate `msg.event.delta.text` into `streamState.accumulatedText`
- [ ] Throttle check: `Date.now() - lastUpdateTime >= interval`
- [ ] Native path: `sendMessageDraft(chatId, draftId, accumulatedText)`
- [ ] Fallback path: `editMessageText(chatId, messageId, accumulatedText)`
- [ ] Guard on messageId readiness (sentinel 0 check) — buffer if not ready

## Phase 3: Assistant/Result Handler Modifications

### 3.1 Modify assistant handler for streaming deduplication
- [ ] Check if `streamState` is active when `assistant` event fires
- [ ] If streaming active + fallback: `editMessageText` with HTML-formatted full text
- [ ] If streaming active + native: `sendMessage` with HTML-formatted full text
- [ ] If no streaming: existing `sendChunked` path unchanged
- [ ] Handle `parse_mode: "HTML"` with plain-text fallback on parse error

### 3.2 Modify result handler for StreamState cleanup
- [ ] Add `cleanupStreamState()` method — null-before-cleanup pattern
- [ ] Call `cleanupStreamState()` in `result` handler if `streamState` exists
- [ ] Clean up in `handleCliExit` for crash scenarios
- [ ] Ensure turn watchdog also cleans up StreamState

## Phase 4: 4096-Char Splitting + Tool Use

### 4.1 Implement message splitting during streaming
- [ ] In `handleTextDelta`: check `accumulatedText.length >= streamSplitThreshold`
- [ ] `finalizeStreamMessage()`: send accumulated text via `sendMessage`, store message_id in `splitMessages`
- [ ] Reset `accumulatedText`, increment `draftId` (native) or get new `messageId` (fallback)
- [ ] Start new streaming message for continuation

### 4.2 Implement tool use pause/resume
- [ ] On `content_block_start` with `type === "tool_use"`: set `streamState.paused = true`
- [ ] Append `"\n\n⚙️ Using [tool]..."` to current stream message
- [ ] On next `content_block_start` with `type === "text"`: set `paused = false`
- [ ] Edit message to remove tool indicator, continue accumulating

## Phase 5: Tests

### 5.1 Streaming lifecycle tests
- [ ] Happy path native: deltas → final HTML message
- [ ] Happy path fallback: draft error → editMessageText path
- [ ] Detection caching: second turn uses cached strategy
- [ ] No deltas: `content_block_start` + `content_block_stop` with zero deltas

### 5.2 Edge case tests
- [ ] 4096 split: accumulated text exceeds threshold → split into two messages
- [ ] Tool use pause/resume: text → tool → text in single turn
- [ ] Race condition: first delta before status message resolves
- [ ] CLI crash mid-stream: process exit → cleanup
- [ ] Interleaved blocks: text → tool → text in single turn

### 5.3 Error handling tests
- [ ] Fallback 429: transient rate limit does NOT trigger permanent fallback
- [ ] Turn watchdog during streaming: 10-minute timeout → cleanup
