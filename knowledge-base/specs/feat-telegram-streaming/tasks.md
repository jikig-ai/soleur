# Tasks: Telegram Streamed Responses

**Plan:** `knowledge-base/plans/2026-03-02-feat-telegram-streamed-responses-plan.md`
**Issue:** #372
**Branch:** feat-telegram-streaming

## Phase 1: Types + CLI Flag + Core Streaming

### 1.1 Verify stream_event envelope shape
- [ ] Run CLI with `--include-partial-messages --output-format stream-json` and capture actual NDJSON
- [ ] Document verified event structure (confirm `{"type": "stream_event", "event": {...}}` envelope)
- [ ] Record exact field paths for text deltas: `msg.event.delta.text`, `msg.event.delta.type`

### 1.2 Define StreamState and extend editMessageText
- [ ] Add `StreamState` interface to `types.ts`: `chatId`, `messageId`, `accumulatedText`, `lastUpdateTime`
- [ ] Add `other?: Record<string, unknown>` parameter to `editMessageText` in `BotApi` interface
- [ ] Update grammY adapter in `index.ts` to forward `other` parameter
- [ ] Verify types compile: `bunx tsc --noEmit`

### 1.3 Add --include-partial-messages to CLI spawn
- [ ] Add `"--include-partial-messages"` to `cliArgs` array in `index.ts`

### 1.4 Add stream_event handling to handleCliMessage
- [ ] Add `"stream_event"` case to the switch in `handleCliMessage`
- [ ] Route `msg.event.type`:
  - `content_block_start` (text only, no active streamState) → init StreamState, clear typingTimer
  - `content_block_delta` (text_delta) → accumulate text, throttled `editMessageText`
  - `content_block_start` (text, streamState active + after tool) → resume, don't reinit
  - All others → no-op

### 1.5 Implement delta accumulation + throttled edit
- [ ] Accumulate `msg.event.delta.text` into `streamState.accumulatedText`
- [ ] Throttle: `Date.now() - lastUpdateTime >= STREAM_EDIT_INTERVAL_MS` (2500ms)
- [ ] Guard on `messageId !== 0` before editing
- [ ] Use plain text (no `parse_mode`) during streaming

### 1.6 Implement 4096-char split during streaming
- [ ] Check `accumulatedText.length >= MAX_CHUNK_SIZE` after accumulation
- [ ] Finalize: `sendMessage(chatId, accumulatedText)` as plain text
- [ ] Start new streaming message: `sendMessage` → store new `messageId` on `streamState`
- [ ] Reset `accumulatedText`

### 1.7 Modify assistant handler for streaming deduplication
- [ ] Check if `streamState` is active when `assistant` event fires
- [ ] If active: `editMessageText(chatId, messageId, html, { parse_mode: "HTML" })`
- [ ] Catch HTML parse error → fall back to plain text edit
- [ ] Skip `sendChunked` for text already streamed
- [ ] Do NOT call `cleanupTurnStatus()` — message is the streaming message

### 1.8 Modify cleanupTurnStatus for streaming
- [ ] When `streamState` is active: null `turnStatus`, clear `typingTimer`, but skip `deleteMessage`
- [ ] When no streaming: existing behavior unchanged

### 1.9 Modify result handler + cleanup
- [ ] Add `cleanupStreamState()`: null `streamState` (no message deletion)
- [ ] Call in `result` handler, `handleCliExit`, and turn watchdog

## Phase 2: Tests

### 2.1 Update test infrastructure
- [ ] Add `other?` parameter support to `editMessageText` mock in `createMockApi()`
- [ ] Create `streamEvent(type, event)` helper for building stream NDJSON

### 2.2 Streaming lifecycle tests
- [ ] Happy path: deltas → progressive edits → final HTML edit
- [ ] 4096 split: accumulated text exceeds threshold → split into two messages
- [ ] No deltas: `content_block_start` + `content_block_stop` → no edit, no error

### 2.3 Edge case tests
- [ ] Race condition: first delta before status message resolves → buffered, flushed later
- [ ] Interleaved blocks: text → tool_use → text → streaming resumes without reinit
- [ ] CLI crash mid-stream → StreamState cleaned up

### 2.4 Error handling tests
- [ ] HTML parse failure on final edit → falls back to plain text
- [ ] Turn watchdog during streaming → StreamState cleaned up
