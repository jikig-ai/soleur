---
title: Agent SDK session resume architecture for multi-turn conversations
date: 2026-03-27
category: integration-issues
tags: [agent-sdk, session-persistence, multi-turn, websocket, supabase]
module: apps/web-platform/server/agent-runner
---

# Learning: Agent SDK session resume architecture

## Problem

Each user message spawned a fresh Agent SDK `query()` with `persistSession: false` — the agent had complete amnesia between turns. The user's actual message was never passed to the agent (hardcoded greeting was used instead).

## Solution

Hybrid architecture: SDK `resume` as primary path, message replay from Supabase as fallback.

1. **SDK resume:** Remove `persistSession: false` (SDK default is `true`). Capture `session_id` from the first streamed message (`message.session_id` — available on every message, not just init). Store in `conversations.session_id`. On subsequent turns, pass `options: { resume: sessionId }` to `query()`.

2. **Message replay fallback:** When resume fails (server restart, container redeploy), load last 20 messages from Supabase, format as conversation context, inject into a fresh `query()` prompt. Loses tool execution context but preserves conversational memory.

3. **WebSocket grace period:** 30-second delay before aborting session on disconnect. Pending disconnect timers are cancelled when the user reconnects. New `resume_session` message type lets clients re-associate with existing conversations.

4. **Lifecycle management:** Inactivity timeout (24h), explicit `close_conversation`, server startup cleanup for orphaned conversations.

## Key Insight

The Agent SDK's `persistSession` defaults to `true` and stores session files at `~/.claude/projects/` — NOT in the workspace directory. In containerized deployments, these files are lost on restart. Any multi-turn architecture using the Agent SDK must include a fallback for cross-restart scenarios. The SDK's `resume` option is a first-class feature that accepts a `session_id` string and restores full conversation context including tool execution history.

The Supabase JS client's `.catch()` cannot be chained on query builders (`PostgrestFilterBuilder`) — you must `await` the result and destructure `{ error }` instead.

## Session Errors

1. **Markdown lint failure (MD032)** — Missing blank lines before lists in spec.md caused commit rejection.
   **Prevention:** Always add blank lines before list items in markdown. Markdownlint pre-commit hook catches this.

2. **Wrong CWD for shell commands** — `cd apps/web-platform` failed because the shell was already inside that directory from a prior command.
   **Prevention:** Use absolute paths for `cd` commands. The Bash tool does not persist directory changes between calls.

3. **Supabase query builder `.catch()` type error** — Chained `.catch()` on `PostgrestFilterBuilder` instead of awaiting the result.
   **Prevention:** Always destructure Supabase query results as `const { data, error } = await supabase.from(...)...` — never chain `.catch()` on the builder.

## Tags

category: integration-issues
module: apps/web-platform/server/agent-runner
