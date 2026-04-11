---
title: "fix: conversation command center state and titles"
type: fix
date: 2026-04-11
issue: "#1962"
deepened: 2026-04-11
updated: 2026-04-11
---

# Fix Conversation Command Center State and Titles

[Updated 2026-04-11] Revised based on brainstorm decisions. Key changes: clickable
status badge (not ellipsis menu), blocked transitions on active conversations,
no Retry action, deferred conversation creation.

## Summary

Three problems in the Command Center conversation inbox:

1. Some conversations display as "Untitled conversation" — `deriveTitle()` has
   no fallback when user messages are missing or only contain @-mentions
2. Users cannot change conversation status — "Needs attention" (failed) stays
   stuck forever with no UI to transition state
3. Junk conversations pollute the inbox — empty rows created at session start
   before any real message is sent

## Brainstorm Reference

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-11-conversation-state-management-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/fix-conversation-state/spec.md`

## Implementation

### 1. Fix Title Derivation

**File:** `apps/web-platform/hooks/use-conversations.ts`

Rewrite `deriveTitle()` (lines 26-33) to accept `domainLeader` as a third
parameter and handle the full fallback chain in one function (reviewer
feedback: avoid splitting logic between `deriveTitle` and enrichment block):

```text
deriveTitle(messages, conversationId, domainLeader?):
1. First user message content (strip @-mentions, truncate to 60 chars)
2. First assistant message content (truncate to 60 chars)
3. If user message exists but was only @-mentions: raw text (before stripping)
4. Domain leader label ("CTO conversation") if domainLeader is set
5. "Untitled conversation"
```

Note: step 2 (assistant message) comes before step 3 (raw @-mention) because
"@cto" is a worse title than a meaningful assistant response (reviewer feedback).

Update the enrichment block (lines 116-127) to pass `conv.domain_leader` to
`deriveTitle()` and remove the separate leader fallback check. The `system`
special case stays in the enrichment block (hardcoded "Project Analysis").

### 2. Add Clickable Status Badge with Dropdown

**File:** `apps/web-platform/components/inbox/conversation-row.tsx`

Replace the read-only `StatusBadge` component with an interactive version:

- **`failed` and `waiting_for_user`:** Badge is clickable. Clicking opens a
  dropdown below/beside the badge with available transition actions.
- **`active`:** Badge is NOT clickable (no visual affordance, no dropdown).
  Agent is running — transitions are blocked.
- **`completed`:** Badge is NOT clickable. Terminal state, no available actions.

**Dropdown actions by status:**

| Current Status | Available Actions |
|---|---|
| `failed` | Dismiss (→ completed) |
| `waiting_for_user` | Mark resolved (→ completed) |
| `active` | (blocked — no dropdown) |
| `completed` | (terminal — no dropdown) |

**Implementation pattern:**

- Follow `components/kb/share-popover.tsx` pattern: `useRef` + `mousedown`
  listener for outside-click dismissal
- `e.stopPropagation()` on the badge click AND each dropdown item to prevent
  row navigation (`onClick → router.push`)
- Position with `absolute` + `z-50` to render above adjacent rows
- Minimum 44x44px touch target for mobile accessibility
- `aria-label` and `role="menu"` for accessibility

**Props change:** `ConversationRow` gains `onStatusChange?: (id, newStatus) => void`.
When provided, `StatusBadge` renders as interactive for applicable statuses.

### 3. Add `updateStatus` to `useConversations` Hook

**File:** `apps/web-platform/hooks/use-conversations.ts`

Add `updateStatus` function to the hook:

1. Capture `conversations` state for rollback
2. Optimistically update local state via `setConversations`
3. Call Supabase: `supabase.from("conversations").update({ status }).eq("id", id)`
4. Destructure `{ error }` (learning: Supabase silent error return values)
5. On error: revert optimistic update, set error state

**Realtime coexistence:** The existing subscription (lines 144-176) will
receive the same UPDATE event ~100-300ms later. The re-application is
idempotent — React reconciliation skips re-render when values match.

**Update `UseConversationsResult` interface** (line 19) to include
`updateStatus: (conversationId: string, newStatus: ConversationStatus) => Promise<void>`.

### 4. Wire Dashboard Page

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

- Destructure `updateStatus` from `useConversations()` (line 98)
- Pass `onStatusChange={updateStatus}` to each `ConversationRow` (line 538)

### 5. Defer Conversation Creation Until First Real Message

**Files:**

- `apps/web-platform/server/ws-handler.ts` (primary)
- `apps/web-platform/server/agent-runner.ts` (adjust `sendUserMessage`)

Currently `start_session` (ws-handler.ts:207) calls `createConversation()`
immediately, creating a DB row before any message is sent. Change to:

**`createConversation` signature change:**

Add optional `id` parameter so a pre-generated UUID can be passed in
(reviewer finding H4: current function generates its own UUID at line 134).

```text
async function createConversation(userId, leaderId?, id?): Promise<string>
```

If `id` is provided, use it instead of calling `randomUUID()`.

**`start_session` handler changes:**

1. Generate a UUID eagerly: `const pendingId = randomUUID()`
2. Do NOT call `createConversation()` — store in session:
   `session.pendingConversationId = pendingId`
   `session.pendingLeaderId = msg.leaderId`
   `session.pendingContext = validatedContext`
3. Send `session_started { conversationId: pendingId }` to client as before
4. For directed sessions (with `leaderId`), do NOT boot the agent yet —
   agent boot also defers to first message

**`chat` handler changes (reviewer findings H2, H3):**

The existing guard at line 308 (`if (!session.conversationId)`) must be
rewritten to also check `session.pendingConversationId`:

```text
if (!session.conversationId && !session.pendingConversationId) {
  // "No active session. Send start_session first."
  return;
}
```

If `session.pendingConversationId` exists (conversation not yet in DB):

1. Check if message content is real (strip @-mentions, check non-empty)
2. If real:
   a. Call `createConversation(userId, session.pendingLeaderId, session.pendingConversationId)`
   b. Set `session.conversationId = session.pendingConversationId`
   c. Clear pending state: `delete session.pendingConversationId`
   d. Call `sendUserMessage()` directly — it handles `saveMessage()` internally
      (reviewer finding H3: do NOT call `saveMessage` separately, that double-saves)
3. If only @-mentions with no content: send error "Please include a
   message along with the @-mention", do NOT create conversation

If `session.conversationId` exists (already created): proceed as normal.

**`close_conversation` handler changes (reviewer finding H1):**

If `close_conversation` fires when only `pendingConversationId` exists (no DB
row yet), clean up the pending state and send `session_ended`. Do NOT attempt
a DB update on a non-existent row:

```text
if (!session.conversationId && session.pendingConversationId) {
  delete session.pendingConversationId;
  sendToClient(userId, { type: "session_ended" });
  return;
}
```

**`resume_session` is unchanged** — it operates on existing conversations only
(verifies ownership at lines 249-259). No pending state involved.

**Risk: Client expects conversationId for URL routing.** The UUID is generated
eagerly and sent in `session_started`, so the client navigates to
`/dashboard/chat/{id}` immediately. The DB row is created when the first real
message arrives. The chat page's message fetch returns empty for new
conversations — same as current behavior.

**Risk: Agent boot timing for directed sessions.** Currently, directed sessions
(`@cto`) boot the agent immediately in `start_session`. With deferred creation,
the agent boots on first `chat` message instead. This adds ~200-500ms latency
to the first response for directed sessions.

**Risk: Realtime INSERT events.** The Realtime subscription (use-conversations.ts
lines 144-176) listens only for UPDATE events. A deferred INSERT won't appear
in the inbox until the next fetch. Mitigation: add `INSERT` to the Realtime
subscription, or accept that new conversations appear on the next poll/refetch.

## Test Scenarios

### Title derivation

- Given a conversation with no messages, when rendered, title shows domain
  leader label (e.g., "CTO conversation") or "Untitled conversation"
- Given a conversation where first user message is "@cto " and an assistant
  message exists, title shows the assistant message content (not "@cto")
- Given a conversation where first user message is "@cto " and no assistant
  message exists, title shows "@cto" (raw message, not empty string)
- Given a conversation with only assistant messages, when rendered, title
  shows the assistant message content

### Status transitions

- Given a conversation with status "failed", when user clicks the status
  badge, a dropdown appears with "Dismiss"
- Given a conversation with status "waiting_for_user", when user clicks the
  badge, a dropdown appears with "Mark resolved"
- Given a conversation with status "active", the status badge is not clickable
- Given a conversation with status "completed", the status badge is not clickable
- Given a failed Supabase update, the status reverts and an error appears

### Deferred conversation creation

- Given a new session, when start_session is sent, no conversation row
  exists in the database
- Given a new session, when the first chat message with real content is sent,
  a conversation row is created
- Given a new session, when only "@cto" is sent with no other content,
  no conversation row is created

## Acceptance Criteria

- [ ] No conversation displays as "Untitled" when it has any messages
- [ ] Failed conversations can be dismissed from the inbox via badge click
- [ ] Waiting conversations can be marked resolved from the inbox via badge click
- [ ] Active conversations have non-clickable status badges
- [ ] Completed conversations have no dropdown actions
- [ ] Starting a session that errors before any message creates no conversation row
- [ ] Sending only "@cto" with no other content does not create a conversation
- [ ] Existing tests in `test/command-center.test.tsx` and
  `test/components/conversation-row.test.tsx` continue passing
- [ ] New tests cover: title fallback, badge click interaction, optimistic update,
  deferred creation

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Race condition between user-initiated and agent-driven transitions
is the highest technical risk — resolved by blocking transitions on active
conversations. Direct Supabase client update is the right pattern since the
command center page has no WS connection. Discriminated union exhaustive
switches must be verified if WSMessage types change. Deferred conversation
creation changes the ws-handler flow significantly — test session lifecycle
thoroughly.

### Product (CPO)

**Status:** reviewed
**Assessment:** Inbox noise compounds over time and undermines Phase 3 "Make it
Sticky" promise. The 4-state model is sufficient for current user count (0
external users). Title persistence and bulk operations can be revisited when
real usage data exists in Phase 4.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** CPO (brainstorm carry-forward)
**Skipped specialists:** ux-design-lead (running in parallel, designs pending)
**Pencil available:** N/A

## Context

- **RLS policy:** "Users can manage own conversations" allows UPDATE via browser client
- **Realtime:** Already subscribed to conversation UPDATE events in `use-conversations.ts:144-176`
- **No migration needed:** Schema supports all four statuses and RLS permits user updates
- **Popover pattern:** `components/kb/share-popover.tsx` provides outside-click reference
- **Key learning:** Supabase JS client silently discards errors unless `{ error }` destructured
- **Key learning:** Vitest mock tracked functions must be at module level before `vi.mock()` factory
