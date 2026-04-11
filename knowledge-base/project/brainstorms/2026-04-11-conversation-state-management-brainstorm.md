# Conversation State Management and UX

**Date:** 2026-04-11
**Issue:** #1962
**Branch:** fix-conversation-state
**Status:** Complete

## What We're Building

Fix the conversation command center so users can manage conversation lifecycle:

1. **Fix untitled conversations** — improve `deriveTitle()` fallback chain so
   conversations always have meaningful titles
2. **Enable user-initiated state transitions** — clickable status badge with
   dropdown menu for transitioning conversations between states
3. **Prevent junk conversations** — defer DB row creation until the first real
   user message with content (not just @-mentions)

## Why This Approach

The command center accumulates noise over time. Failed conversations show
"Needs attention" forever with no escape hatch. Some conversations appear as
"Untitled" because the title derivation function has no meaningful fallback
when messages are missing or only contain @-mentions. Empty conversations
(session errored before any message) pollute the inbox.

The approach is minimal: no new DB states, no migrations for status, no
server-side title column. Direct Supabase client updates leverage existing RLS
policy. The existing Realtime subscription propagates changes automatically.

## Key Decisions

| Decision | Choice | Alternatives Considered |
|----------|--------|------------------------|
| State model | Keep existing 4 states (active, waiting_for_user, completed, failed) | Add 'archived' state; add archived_at timestamp column |
| Title strategy | Fix client-side deriveTitle() fallback chain | Persist title column server-side |
| Junk conversations | Defer DB creation until first real message | Garbage-collect empty rows; filter from query |
| UX pattern | Clickable status badge with dropdown | Ellipsis menu on row; swipe actions |
| Active session conflict | Block transitions on active conversations | Abort session then transition; last-writer-wins |
| Mutation path | Direct Supabase client update (optimistic + Realtime) | REST API endpoint |

## State Machine

### Server-Driven Transitions (existing, unchanged)

```text
active → waiting_for_user   (agent hits review gate / stream ends)
waiting_for_user → active   (user responds to review gate)
active → completed          (close_conversation WS message)
waiting_for_user → completed (2hr inactivity timeout)
active → failed             (error, abort, disconnect)
waiting_for_user → failed   (server startup cleanup, >5min stale)
```

### User-Initiated Transitions (new)

```text
failed → completed           ("Dismiss")
waiting_for_user → completed ("Mark resolved")
active → completed           BLOCKED when agent is running
completed → (none)           Terminal state, no actions
```

The status badge is not clickable when the conversation is `active` (agent
running). The badge is clickable for `failed` and `waiting_for_user` states.
Completed conversations show no dropdown (terminal state).

## Title Derivation Fallback Chain

```text
1. First user message content (strip @-mentions, truncate to 60 chars)
2. If empty after stripping: raw first user message text (before stripping)
3. First assistant message content (truncate to 60 chars)
4. Domain leader label ("CTO conversation", "CMO conversation")
5. "Untitled conversation"
```

## Junk Conversation Prevention

Currently, `ws-handler.ts` creates a conversation row at `start_session` time,
before any messages exist. Change to:

- `start_session` creates an in-memory session state (no DB row)
- First real user message (content after stripping @-mentions is non-empty)
  triggers the conversation INSERT + message INSERT in the same transaction
- If the session errors before a real message, no DB row is created
- Messages that are only @-mentions (e.g., "@cto") without additional content
  do not trigger conversation creation

## Open Questions

- **Bulk dismiss:** If 20+ conversations are stuck in "needs attention", users
  must dismiss them one by one. Bulk actions are deferred (Phase 3 non-goal)
  but may need revisiting if this becomes painful.
- **Re-opening:** Completed is terminal. If users need to re-open, that's a
  future scope change requiring a new transition.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales,
Finance, Support

### Engineering (CTO)

**Summary:** Race condition between user-initiated and agent-driven transitions
is the highest technical risk. REST endpoint recommended over WS for inbox
mutations since the command center page has no WS connection. Direct Supabase
client update resolves this more simply. Discriminated union exhaustive
switches must be verified if WSMessage types change.

### Product (CPO)

**Summary:** Inbox noise compounds over time and undermines the Phase 3
"Make it Sticky" promise. The 4-state model is sufficient for current user
count (0 external users). Title persistence and bulk operations can be
revisited when real usage data exists in Phase 4.
