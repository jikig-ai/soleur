# Learning: Supabase JS client silently discards errors unless you destructure { error }

## Problem

`saveMessage()` and `updateConversationStatus()` in `agent-runner.ts` called the Supabase JS client without checking the `{ error }` return value. The client does **not** throw on failures — it returns `{ data, error }`. This meant:

- Insert failures in `saveMessage` silently lost messages (user sees streamed response, but on reload it's gone)
- Update failures in `updateConversationStatus` left conversations in stale statuses, breaking UI indicators

Additionally, the `updateConversationStatus("failed")` call inside `startAgentSession`'s catch block could throw an unhandled rejection if the newly-throwing function failed — on Node 22, this crashes the entire server process.

## Solution

1. Destructure `const { error }` from both Supabase calls and throw on error — matching the existing pattern in `createConversation()` and `getUserApiKey()`
2. Wrap the catch-block `updateConversationStatus("failed")` with `.catch()` to prevent unhandled rejection, matching the existing defensive pattern in `sendUserMessage`

## Key Insight

The Supabase JS client (v2.58.0) deliberately returns `{ data, error }` instead of throwing. Every Supabase query result must be destructured and checked. The `throwOnError()` API exists but changes the contract for the entire chain — per-call `if (error)` checks are correct for incremental fixes. When adding throws to functions called from catch blocks, always add a nested `.catch()` error boundary to prevent unhandled rejections.

## Related

- [fire-and-forget-promise-catch-handler](2026-03-20-fire-and-forget-promise-catch-handler.md) — same class of catch-block error boundary
- [websocket-error-sanitization-cwe-209](2026-03-20-websocket-error-sanitization-cwe-209.md) — thrown errors are sanitized before reaching clients
- Issues: #838, #839

## Tags

category: runtime-errors
module: web-platform/agent-runner
