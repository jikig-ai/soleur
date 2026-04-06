# Telegram Streamed Responses Brainstorm

**Date:** 2026-03-02
**Issue:** #372
**Status:** Complete
**Branch:** feat-telegram-streaming

## What We're Building

Real-time response streaming for the Telegram bridge. Instead of waiting for Claude to finish generating and sending the complete response at once, users will see text appear progressively as it's generated.

**Primary approach:** Use Telegram's native `sendMessageDraft` API (Bot API 9.5, available to all bots as of March 1, 2026) for smooth animated streaming. Fall back to `editMessageText` progressive updates if the native API errors.

## Why This Approach

1. **`sendMessageDraft` is the direction Telegram is going** — purpose-built for AI assistant streaming. Smooth animated text vs. jumpy edits every 2-3 seconds.
2. **Fallback to `editMessageText` keeps us safe** — the native API just became universally available (literally March 1, 2026). Known issues like `TEXTDRAFT_PEER_INVALID` in some private chat scenarios mean we can't rely on it exclusively yet.
3. **The bridge already ignores streaming data it receives** — the CLI emits `content_block_delta` events via `--output-format stream-json`, but the bridge discards them. We're leaving UX on the table.
4. **The existing status message pattern proves the architecture works** — throttled `editMessageText` with `Date.now()` guards is already battle-tested for the "Thinking..." status. The fallback path reuses this directly.

## Key Decisions

### 1. Streaming Strategy: Native-first with progressive fallback

- **Primary:** `sendMessageDraft` for smooth animated text
- **Fallback:** `editMessageText` with 2-3s throttled updates
- **Detection:** Try `sendMessageDraft` on first turn, catch errors, cache the result for the session
- **Rationale:** Best UX when native works, graceful degradation when it doesn't

### 2. Mid-stream Formatting: Plain text during stream, HTML on final

- Stream raw text without markdown conversion during generation
- When the response completes, replace with properly formatted HTML via existing `markdownToHtml` + `sendChunked` pipeline
- **Rationale:** Partial markdown produces broken HTML (unclosed code blocks, incomplete bold). Plain text is safe and readable. Final HTML delivery preserves the polished formatting users expect.

### 3. Long Message Handling: Finalize current + start new

- When approaching 4096-char Telegram limit mid-stream, finalize the current draft/message
- Start a new streaming message for the remainder
- User sees multiple messages building progressively
- **Rationale:** Better than truncating (user sees everything in real-time) and simpler than buffering

### 4. Tool Use During Streaming: Pause and show status

- When a `tool_use` event arrives mid-stream, pause text streaming
- Show a status indicator (reuse existing "Using [tool]..." pattern)
- Resume streaming when text content continues
- **Rationale:** Users understand why text paused. Matches the existing UX expectation.

## Technical Context

### Current Architecture

- `Bridge` class in `bridge.ts` handles CLI message routing
- `handleCliMessage` switch only processes: `system`, `assistant` (complete), `result`
- `content_block_delta`, `content_block_start`, `content_block_stop` events are logged and discarded
- `BotApi` interface: `sendMessage`, `editMessageText`, `deleteMessage`, `sendChatAction`
- `TurnStatus` tracks: message ID, tool uses, timing — already handles async lifecycle

### What Changes

- Add `content_block_start`, `content_block_delta`, `content_block_stop` cases to `handleCliMessage`
- New `StreamState` type (separate from `TurnStatus`) for accumulated text, message IDs, strategy
- Extend `BotApi` with `sendMessageDraft` method
- New streaming logic: accumulate deltas → throttled draft/edit updates → finalize on complete
- Status-to-streaming transition: repurpose "Thinking..." message or replace it

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `sendMessageDraft` errors in private chats | High | Fallback to `editMessageText` on error |
| Partial markdown → broken HTML | High | Plain text during stream, HTML only on final |
| Telegram rate limits on `editMessageText` (~30/min) | Medium | 2-3s throttle, only applies to fallback path |
| `TurnStatus` state overload | Medium | Separate `StreamState` type |
| Tool use interrupting text stream | Medium | Pause/resume with status indicator |
| 4096-char message limit mid-stream | Medium | Finalize + start new message |
| grammY lacks `sendMessageDraft` support | Low | Use raw `bot.api.raw.sendMessageDraft` call |

### Institutional Learnings Applied

- **P1-012 fix:** Never chain cleanup to delivery via `.then()` — streaming cleanup follows same pattern
- **Throttle pattern:** Use `Date.now()` time-checks, not `setTimeout` timers
- **Readiness guards:** Check `messageId !== 0` before any edit/draft call
- **State nulling:** Null-out streaming state before async cleanup to prevent races

## Open Questions

1. **grammY `sendMessageDraft` support** — Does grammY v1.40.0 expose this method natively, or do we need raw API calls? Need to check grammY changelog/types.
2. **Exact `content_block_delta` event shape** — Verify field names (`delta.text`, `delta.type`, `index`) from actual CLI output.
3. **`sendMessageDraft` rate limits** — Telegram docs don't specify. Need empirical testing.
4. **Draft-to-message finalization** — Does `sendMessageDraft` automatically become a message when complete, or do we need to send a final `sendMessage`?

## Success Criteria

- Users see text appearing progressively during generation (< 2s latency from CLI delta to Telegram update)
- Long responses (> 4096 chars) display correctly across multiple messages
- Tool use shows status indicator, then streaming resumes
- Final message is properly HTML-formatted
- Fallback path works when native streaming is unavailable
- No regression in existing bot functionality (commands, error handling, health check)
- Test coverage for streaming lifecycle, fallback logic, and edge cases
