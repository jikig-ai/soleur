---
title: "WebSocket close code routing prevents infinite reconnect loop"
date: 2026-03-27
category: runtime-errors
module: web-platform/ws-client
tags: [websocket, close-codes, reconnection, teardown, state-management]
---

# Learning: WebSocket close code routing prevents infinite reconnect loop

## Problem

The command center chat interface was stuck on "Reconnecting..." when entering it. Users saw an infinite reconnect cycle with exponential backoff instead of actionable feedback (e.g., redirect to login or a meaningful error message).

## Root Cause

The WebSocket client's `onclose` handler in `ws-client.ts` ignored the `CloseEvent.code` property entirely. Every close event -- regardless of reason -- triggered the same exponential backoff reconnection logic. This meant non-transient server-initiated closes (auth failure 4001, T&C not accepted 4004, superseded connection 4002, internal error 4005) all resulted in futile reconnection attempts that would never succeed.

The server was correctly sending typed close codes (established in the 2026-03-17 and 2026-03-18 WebSocket sessions), but the client was discarding that information. The `key_invalid` error code handler in the message protocol already had a proper teardown pattern (mountedRef, clearTimeout, onclose=null, close), but it only covered application-layer errors -- transport-layer close codes had no equivalent routing.

## Solution

Added a `NON_TRANSIENT_CLOSE_CODES` routing map and `teardown()` helper to `ws-client.ts`. The `onclose` handler now branches on `CloseEvent.code`:

- **Auth failures (4001/4003)** -- redirect to `/login`
- **T&C rejection (4004)** -- redirect to `/accept-terms`
- **Superseded connection (4002)** -- disconnect quietly (no user-visible error)
- **Server error (4005)** -- disconnect with reason displayed in UI
- **All other codes** -- reconnect with exponential backoff (unchanged behavior)

Extracted `teardown()` from the existing `key_invalid` message handler to enforce the same shutdown sequence (set mountedRef false, clearTimeout, null out onclose, close socket) in both code paths. This prevents the reconnect timer from firing after a non-transient close decision has been made.

Added `disconnectReason` state to the hook so the `StatusIndicator` component can show actionable feedback ("Session expired -- redirecting to login") instead of the generic "Disconnected" message.

During review, simplified the routing map by removing a redundant `action` field -- redirect vs. disconnect behavior is derivable from whether a `target` URL is present in the map entry.

## Key Insight

WebSocket close codes are a routing signal, not just a diagnostic log line. RFC 6455 defines the 4000-4999 range specifically for application-defined semantics. When a server sends a typed close code, the client `onclose` handler must route on it the same way an HTTP client routes on status codes -- some codes mean "retry" (like HTTP 503), others mean "stop and redirect" (like HTTP 401), and others mean "stop silently" (like a controlled shutdown). Treating all close events as transient failures is the WebSocket equivalent of retrying every HTTP error, including 401s and 403s.

The pattern generalizes: any reconnecting client (WebSocket, SSE, gRPC stream) should maintain a map of non-transient close/error codes with associated recovery actions. The default branch should be "reconnect with backoff" -- but the map must exist, even if initially empty, because every server eventually adds close codes that should not trigger reconnection.

## Session Errors

1. **Markdown lint failure on session-state.md** -- Missing blank lines around headings and lists in a generated markdown file caused a pre-commit lint check to fail. Prevention: Always include blank lines before and after headings, lists, and fenced code blocks in generated markdown files.

2. **Wrong working directory during test execution** -- Accidentally ran commands from `apps/web-platform/` instead of the worktree root after using `cd` during test command exploration. Recovery required using the absolute worktree path. Prevention: Always use absolute paths in Bash commands; avoid `cd` without returning to the original directory.

## Tags

category: runtime-errors
module: web-platform/ws-client
related: 2026-03-17-websocket-cloudflare-auth-debugging, 2026-03-18-typed-error-codes-websocket-key-invalidation, 2026-03-20-websocket-first-message-auth-toctou-race
