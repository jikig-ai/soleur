---
title: "WebSocket cumulative vs delta streaming: replace not append"
date: 2026-04-13
category: runtime-errors
tags: [websocket, streaming, chat, state-machine]
symptoms: ["duplicate text in chat bubbles", "two bubbles per agent turn", "text doubles on each stream event"]
module: apps/web-platform
synced_to: null
---

# Learning: WebSocket cumulative vs delta streaming

## Problem

Every agent response in the chat UI produced broken output: duplicate bubbles,
doubled/tripled text content, and no visual indication of completion. The root
cause was a protocol ambiguity: the server sent cumulative text snapshots via
`partial: true` messages (full text so far), but the client appended each
message's content as if it were a delta. Three cumulative partials "A", "AB",
"ABC" produced "AABABC" instead of "ABC".

A secondary issue: the server also sent a final `partial: false` message with
the complete text after streaming was done, causing another duplication layer.

## Solution

Three coordinated changes across server, client, and component:

1. **Server** (`agent-runner.ts`): Track `hasStreamedPartials` flag. Skip
   `partial: false` emission when partials were already sent. Emit `tool_use`
   events when the SDK invokes tools.

2. **Client** (`ws-client.ts`): Replace `content: prev.content + msg.content`
   with `content: msg.content` (replace, not append). Add per-message `state`
   field tracking (`thinking -> tool_use -> streaming -> done -> error`). Add
   30s timeout for stuck states.

3. **Component** (`page.tsx`): Replace `isStreaming` boolean with state-driven
   rendering. Each state has distinct visual treatment (pulsing border, status
   chip, checkmark, error banner).

## Key Insight

When a WebSocket protocol sends cumulative snapshots (full text so far), the
client MUST replace content on each event, not append. The `partial` boolean
on the wire message was the contract indicator, but the client never checked it.
Always verify whether a streaming protocol uses cumulative or delta semantics
before writing the client handler.

## Session Errors

1. **`npx vitest` resolved to wrong global version** -- the global npx cache
   had a vitest version with missing native bindings. Prevention: always use
   `node_modules/.bin/vitest` for project-local test runs.

2. **Git pathspec mismatch from wrong CWD** -- shell was in `apps/web-platform/`
   but git add used paths from repo root. Prevention: use relative paths or
   verify CWD before git operations.

3. **TypeScript exhaustive check failed for new WSMessage type** -- adding
   `tool_use` to the WSMessage union required updating the exhaustive switch
   in `ws-handler.ts`. Prevention: after adding a variant to a discriminated
   union, run `tsc --noEmit` immediately to find all exhaustive checks.

4. **Existing test expected ThinkingDots without state field** -- the new
   state-driven rendering broke the backward-compatible case where messages
   have no `state` field. Prevention: when changing component rendering
   conditions, grep for existing test assertions that rely on the old
   conditions.

## Tags

category: runtime-errors
module: apps/web-platform
