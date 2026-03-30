---
status: pending
priority: p3
issue_id: "1289"
tags: [code-review, security]
---

# Add WebSocket message size limit

## Problem Statement

WebSocketServer has no `maxPayload` — defaults to 100 MiB. Authenticated users can send oversized messages causing memory pressure and API cost amplification. Pre-existing issue, not introduced by this PR.

## Proposed Solutions

Add `maxPayload: 64 * 1024` to WebSocketServer config and validate `msg.content` length in the `chat` handler.

## Technical Details

- Affected file: `server/ws-handler.ts` (WebSocketServer constructor)
- Estimated effort: Small
