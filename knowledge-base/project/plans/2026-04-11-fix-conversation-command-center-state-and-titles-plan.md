---
title: "fix: conversation command center state and titles"
type: fix
date: 2026-04-11
issue: "#1962"
---

# Fix Conversation Command Center State and Titles

Two bugs in the Command Center make conversations hard to manage:

1. Some conversations display as "Untitled conversation" when the first user message is missing or empty
2. Users cannot change conversation status -- "Needs attention" (failed) stays stuck forever because there is no UI to transition state

## Root Cause Analysis

### Untitled Conversations

`deriveTitle()` in `hooks/use-conversations.ts:26-32` returns "Untitled conversation" when:

- No user-role message exists for the conversation (e.g., the message insert failed after conversation creation)
- The first user message is only `@leader` mentions with no remaining content after stripping

The `domain_leader === "system"` case is already handled (hardcoded to "Project Analysis"), but general conversations without user messages fall through.

### Stuck Status

The `ConversationRow` component in `components/inbox/conversation-row.tsx` is purely navigational -- clicking always goes to `/dashboard/chat/[id]`. There is no mechanism for the user to mark a "failed" conversation as "completed" (dismissing the error) or to archive/complete conversations they no longer need.

The RLS policy (`"Users can manage own conversations" for all using (auth.uid() = user_id)`) already permits client-side updates, so no migration is needed.

## Acceptance Criteria

- [ ] Conversations with no user messages display a meaningful fallback title (e.g., first assistant message content, or leader-specific label like "CTO conversation")
- [ ] Conversations where the first user message is only @-mentions after stripping display the raw message instead of empty string
- [ ] Each conversation row has a status-change action (click/menu) that allows the user to transition status
- [ ] Valid transitions: any status -> "completed" (dismiss/archive), "failed" -> "active" (retry), "waiting_for_user" -> "completed" (dismiss)
- [ ] Status change persists to Supabase and updates UI immediately (optimistic update)
- [ ] Realtime subscription already in `use-conversations.ts` picks up the persisted change
- [ ] Existing tests in `test/command-center.test.tsx` and `test/components/conversation-row.test.tsx` continue passing
- [ ] New tests cover: title fallback scenarios, status change UI interaction, optimistic update behavior

## Implementation

### 1. Fix Title Derivation (`hooks/use-conversations.ts`)

**File:** `apps/web-platform/hooks/use-conversations.ts`

Update `deriveTitle()` to handle edge cases:

```typescript
function deriveTitle(messages: Message[], conversationId: string): string {
  const firstUserMsg = messages.find(
    (m) => m.conversation_id === conversationId && m.role === "user",
  );
  if (firstUserMsg) {
    const content = firstUserMsg.content.replace(/@\w+\s*/g, "").trim();
    if (content.length > 0) {
      return content.length > 60 ? `${content.slice(0, 57)}...` : content;
    }
    // User message was only @-mentions -- use the raw message
    const raw = firstUserMsg.content.trim();
    if (raw.length > 0) {
      return raw.length > 60 ? `${raw.slice(0, 57)}...` : raw;
    }
  }

  // Fallback: use first assistant message content
  const firstAssistantMsg = messages.find(
    (m) => m.conversation_id === conversationId && m.role === "assistant",
  );
  if (firstAssistantMsg) {
    const stripped = firstAssistantMsg.content.replace(/[#*`_~\[\]()]/g, "").trim();
    if (stripped.length > 0) {
      return stripped.length > 60 ? `${stripped.slice(0, 57)}...` : stripped;
    }
  }

  return "Untitled conversation";
}
```

Also update the enrichment logic to use domain_leader as fallback context:

```typescript
const title = conv.domain_leader === "system"
  ? "Project Analysis"
  : deriveTitle(messages, conv.id) === "Untitled conversation" && conv.domain_leader
    ? `${conv.domain_leader.toUpperCase()} conversation`
    : deriveTitle(messages, conv.id);
```

### 2. Add Status Change to ConversationRow (`components/inbox/conversation-row.tsx`)

**File:** `apps/web-platform/components/inbox/conversation-row.tsx`

Add a context menu or action button that allows the user to change conversation status. Use a dropdown menu triggered by a "..." button (consistent with common inbox patterns). Stop event propagation so clicking the menu does not navigate.

Allowed transitions (simplified -- any user-initiated change is valid since the user owns the conversation):

- "Mark as completed" (any -> completed)
- "Mark as active" (failed/completed -> active)

### 3. Add Status Update Function to `use-conversations.ts`

**File:** `apps/web-platform/hooks/use-conversations.ts`

Export a `updateStatus` function from the hook that:

1. Optimistically updates the local state
2. Calls `supabase.from("conversations").update({ status, last_active }).eq("id", id)`
3. On error, reverts the optimistic update and surfaces the error

```typescript
const updateStatus = useCallback(async (conversationId: string, newStatus: ConversationStatus) => {
  // Optimistic update
  setConversations((prev) =>
    prev.map((c) =>
      c.id === conversationId
        ? { ...c, status: newStatus, last_active: new Date().toISOString() }
        : c,
    ),
  );

  const supabase = createClient();
  const { error } = await supabase
    .from("conversations")
    .update({ status: newStatus, last_active: new Date().toISOString() })
    .eq("id", conversationId);

  if (error) {
    // Revert on failure
    fetchConversations();
    setError(`Failed to update status: ${error.message}`);
  }
}, [fetchConversations]);
```

### 4. Update Hook Return Type

Return `updateStatus` from `useConversations` and pass it through to `ConversationRow`.

### 5. Update Dashboard Page

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Pass `updateStatus` from the hook to each `ConversationRow` as a prop.

## Test Scenarios

- Given a conversation with no messages, when the command center renders, then the title shows the domain leader label (e.g., "CTO conversation") instead of "Untitled conversation"
- Given a conversation where the first user message is "@cto ", when the command center renders, then the title shows "@cto" (raw message)
- Given a conversation with only assistant messages, when the command center renders, then the title shows the assistant message content
- Given a conversation row with status "failed", when the user clicks the action menu and selects "Mark as completed", then the status badge changes to "Completed" immediately and the Supabase update is called
- Given a failed Supabase update, when the user tries to change status, then the status reverts and an error message appears
- Given a conversation with status "waiting_for_user", when the user marks it as "completed", then the row updates and the Realtime subscription does not conflict

## Context

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-07-conversation-inbox-brainstorm.md`
- **RLS policy:** "Users can manage own conversations" allows UPDATE via browser client
- **Realtime:** Already subscribed to conversation UPDATE events in `use-conversations.ts:144-176`
- **No migration needed:** Schema already supports all four statuses and RLS permits user updates
- **Key pattern:** Optimistic updates match the existing Realtime subscription -- the subscription will receive the change after Postgres processes it, but the UI updates immediately

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- bug fix for existing UI component with no new user flows, no architectural changes, no external service integration.
