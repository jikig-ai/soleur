---
module: KB Chat
date: 2026-04-16
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Cost estimate not displayed when resuming a KB chat conversation"
  - "Messages load correctly on resume but usageData remains null"
  - "Both resume paths (sidebar and direct) missing cost data"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [kb-chat, cost-estimate, resume, supabase-numeric, functional-updater]
synced_to: []
---

# Learning: KB chat cost estimate not restored on conversation resume

## Problem

When resuming a KB chat conversation (reopening the sidebar on a document with prior messages), the cost estimate was missing despite messages loading correctly. The `usageData` state remained `null` because neither the API endpoint nor the client fetch path included cost data.

## Root Cause

Three gaps in the data flow:

1. **Server (`api-messages.ts`):** The conversation ownership query used `.select("id")` — cost columns (`total_cost_usd`, `input_tokens`, `output_tokens`) were never fetched.
2. **Client (`ws-client.ts`):** `fetchConversationHistory` returned only `ChatMessage[]` — no cost data parsing.
3. **Resume effects:** Neither the mount-time effect nor the `realConversationId` effect seeded `usageData` from the fetch result.

The cost data existed in the database (persisted via `increment_conversation_cost` RPC) but was never returned to the client on resume.

## Solution

1. Expanded the conversation query in `api-messages.ts` to select cost columns and include them in the response with `Number(conv.total_cost_usd ?? 0)` conversion (PostgREST returns `NUMERIC(12,6)` as strings).
2. Changed `fetchConversationHistory` return type from `ChatMessage[] | null` to `{ messages, costData } | null`.
3. Extracted a `seedCostData()` helper that both resume effects call: `setUsageData(prev => prev ?? costData)`.

## Key Insight

When piggybacking new data on an existing endpoint, the functional updater pattern (`prev => prev ?? newData`) prevents race conditions where a WebSocket event (real-time data) arrives before the HTTP fetch (historical data) resolves. The `??` operator ensures the first non-null value wins, avoiding stale snapshot overwrites.

Supabase `NUMERIC(12,6)` columns are returned as strings by PostgREST — always use `Number()` conversion before including in JSON responses consumed by JavaScript comparison operators.

## Session Errors

1. **Vitest CWD mismatch:** Rule `cq-in-worktrees-run-vitest-via-node-node` prescribes `node node_modules/vitest/vitest.mjs run` but vitest is installed at app level (`apps/web-platform/node_modules/`), not root. Must run from `apps/web-platform/` directory.
   **Recovery:** Found correct binary at `apps/web-platform/node_modules/.bin/vitest`.
   **Prevention:** Clarify rule with CWD note — when vitest is app-level, `cd` to the app directory first.

2. **git add CWD drift:** Ran `git add apps/web-platform/...` while CWD was `apps/web-platform/`, doubling the path.
   **Recovery:** Used explicit `cd` to worktree root before `git add`.
   **Prevention:** Always use absolute paths for git commands or verify CWD first.

## Related

- [Missing resume_session on existing conversations](../runtime-errors/2026-04-12-missing-resume-session-on-existing-conversations.md)
- [KB chat resume empty messages](../ui-bugs/2026-04-16-kb-chat-resume-empty-messages.md)
- GitHub issue: #2436

## Tags

category: ui-bugs
module: KB Chat
